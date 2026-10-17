# Tjugofemte, plan and architecture

Personal budgeting app for iPhone. Pulls booked transactions from one bank account through Enable Banking, categorizes them, and shows what is left to save per payday period. No server, no accounts, no analytics. The app itself talks only to Enable Banking's API; connecting a bank opens the system browser to Enable Banking's login page, the bank and BankID. Everything else stays on the phone, outside backups.

## Decisions taken (grill, 2026-10-17)

| Topic | Decision | Reason |
|---|---|---|
| Money model | Free, open source | Enable Banking terms (updated 2026-01-09) allow production use only for "the personal use of private individuals", no commercial purpose. Same posture as Firefly III and Actual Budget. |
| Platform | iOS only, native Swift, SwiftUI | Signing stays in the Security framework with no JS layer. Fewer native seams. Carl has shipped Swift three times. |
| Key | RSA-4096 generated on the phone (matches Enable Banking's openssl example), stored in the Keychain, class "when unlocked, this device only". Public key exported as SPKI PEM and pasted into the control panel. No .pem import. | Control panel accepts an externally generated public key (verified). Honest claim: the key never exists as a file, is bound to this device, never backed up, and is readable only by the app process on an unlocked phone. Secure Enclave cannot hold it because it is P-256 only and Enable Banking is RS256 only (refuter, Apple docs). |
| Redirect | Custom scheme `tjugofemte://callback` if the control panel accepts it; otherwise HTTPS universal link on the project's GitHub Pages with the hole disclosed. ASWebAuthenticationSession, non-ephemeral, plus a second receive path through `onOpenURL` with the state nonce persisted before the flow starts. | FAQ says default browser, not WebView, and warns BankID may return the user in Safari proper; then the final redirect reaches the app via open-URL, not the session's completion handler. A stolen code is useless without the key, so scheme hijack is moot. |
| Period | Payday period, start day configurable, default 25, moved to the previous Swedish banking day. Banking-day calendar = public holidays plus midsommarafton, julafton and nyårsafton. One-off manual override of a period start for employer-specific rules. Labeled by the month it mostly covers. | Calendar months put two salaries in one month after payday. Public holidays alone get December wrong: banks pay 23 December 2026, not the 24th (Handelsbanken payout table, refuter). |
| Accounts | One account in the budget, chosen after linking. Own-account transfers detected from the session's account identifiers and excluded from income and spending. | Multi-account needs pair matching; not MVP. |
| Transactions | Booked only (status BOOK). Dedup key: transaction_id, else entry_reference, else fingerprint of date, amount, currency, normalized counterparty. | Pending rows change id and amount when they book. |
| At rest | SQLite via GRDB in its own directory, file protection class complete, the whole directory excluded from backup (covers the -wal and -shm sidecars). Keychain items "this device only". UserDefaults holds only language and UI preferences. No SQLCipher. | Backup is the real leak; the directory exclusion closes it. |
| Review | Demo mode with sample data in the MVP; request Apple's prior approval for demo mode in lieu of a demo account (guideline 2.1). If guideline 5.1.1(ix) or 3.2.1(viii) is raised, publish under the company team instead of the individual one; both exist on this Mac. | Reviewer cannot register an Enable Banking app or use BankID. The guidelines are "should" rules at reviewer discretion (refuter, verbatim text on file). |
| Savings math | Plan number: savings target = planned income minus sum of category budgets, fixed at period start. Actual income is compared to plan, never added. Three defined numbers per period (below). Every derived number has an on-screen "how is this calculated" line. | Gives a number to act on at payday; avoids double counting manual income entries. |
| Name | Tjugofemte | |

Defaults chosen without a question (change on request): history kept 3 months by default, options 12 and 24; consent reminder 14 days and 3 days before expiry; rule precedence is user rules first, newest first, then defaults, first match wins; a manual category on a transaction sticks across refetches; recategorizing offers "always put this merchant here"; iOS 18 minimum (Xcode 26.6 on this Mac, iOS 26.5 simulator installed); copy buttons use a local-only pasteboard so the public key and Application ID do not travel through Universal Clipboard.

### The three numbers, defined

1. **Savings target** = planned income minus the sum of category budgets, fixed when the period starts. Shown as "move this on payday". Once the main salary has booked below plan, a second line shows the target adjusted for the shortfall; the original is not silently rewritten.
2. **Budget vs actual per category** = budget minus booked spending in that category. An incoming transaction can be assigned to a spending category as a reimbursement (a Swish back for a split bill), which reduces that category's actual instead of counting as income.
3. **Left over so far** = booked income minus booked spending minus the savings target already moved. Defined exactly this way on the screen.

Quarterly items (CSN): the plan shows the amount to set aside per period, and the comparison runs on the quarter, "set aside 3 × 1,000, paid 0 of 3,000 so far", not per period. No fake per-period over/under.

Income sources are matched, not guessed. Each planned income source (salary, partner, CSN) carries an optional keyword rule run by the same engine as the categories. An incoming transaction that matches becomes that source's actual; unmatched incoming goes to "other income". The adjusted-target line fires when a source's matched actual is below its plan once the period is a few days old. A source with no rule (partner pays the landlord directly) has no actual and is plan-only. This is schema in step 1.

## Architecture

Three targets in one Xcode project, generated with XcodeGen like Vitals and Luma.

**EnableBankingKit** (Swift package, no UI, no GRDB)
- `TokenSigner` protocol. `KeychainRSASigner` now (SecKeyCreateSignature, RS256). A `RemoteSigner` can be added later for a commercial setup, which needs a small signing server plus App Attest; nothing else changes.
- `EnableBankingClient`: the only type in the codebase that touches the network. Refuses any URL whose host is not `api.enablebanking.com`. Sends the full PSU header set on every call (the FAQ says all or none): `Psu-Ip-Address` is the device's own interface address from getifaddrs, since the app never fetches without the user present and must not call another host to learn its public IP; `Psu-User-Agent` is the app's identifier. This keeps fetches out of the 4-per-day background limit. If a bank rejects the private address, fall back to no PSU headers plus a six-hour backoff on `ASPSP_RATE_LIMIT_EXCEEDED`.
- Public key export: SecKey gives PKCS#1; the kit wraps it in SubjectPublicKeyInfo PEM (`-----BEGIN PUBLIC KEY-----`), with a unit test that round-trips through `openssl`.
- Flow: `GET /aspsps?country=SE`, `POST /auth` (psu_type personal, valid_until from the bank's maximum_consent_validity, state nonce), code from the callback, `POST /sessions`, `GET /accounts/{uid}/transactions` with date_from, status BOOK, continuation_key loop that tolerates empty pages (Swedbank history older than 90 days).
- Models keep six fields: date, amount, currency, counterparty text, bank transaction id or entry reference, dedup key. The rest of the response is dropped at decode time.
- Session expiry and EXPIRED_SESSION map to one `needsReauth` state.
- `DELETE /sessions/{session_id}` ("PSU's bank consent will be closed automatically if possible", verified in the API reference) is called by "Delete everything" and by "Disconnect bank" before anything local is wiped, so consent does not linger at the bank for the rest of its 180 days. The data page adds: to revoke completely, also delete the application in the control panel, with the link.

**BudgetCore** (Swift package, pure logic, fully unit tested)
- `PayPeriod`: date to period, period boundaries with banking-day adjustment, Swedish holiday table.
- `Categorizer`: keyword rules over counterparty text, default rules (sv merchants), own-account transfer detection, refund guard for income.
- `DedupKey`.
- `BudgetMath`: planned income, budgets, quarterly spread, savings target, budget vs actual, left over so far, with a `Explanation` value that the UI renders as the "how is this calculated" line.
- `CSVExporter`, `RetentionPolicy`.

**Tjugofemte** (iOS app, SwiftUI)
- `Store`: GRDB, one database file with protection class complete and `isExcludedFromBackup`. Tables: transactions, categories, rules, budgets, income_sources, settings.
- `Keychain`: RSA key, Application ID, session id, account uid. All "this device only".
- `AuthCoordinator`: ASWebAuthenticationSession, non-ephemeral so cookies are shared with Safari if BankID returns the user there. Two receive paths: the session's completion handler and the scene's `onOpenURL` (scheme registered in CFBundleURLTypes). The state nonce is persisted before the flow starts so a kill in the background does not lose it; when the URL arrives via `onOpenURL`, the presented session is cancelled. The HTTPS fallback page carries a visible "Open Tjugofemte" button.
- `Notifications`: local reminders scheduled at session creation.
- Screens: Onboarding guide (sv/en, step by step with copy buttons), Connect, Account picker, Overview (period, savings target, left over, budget vs actual), Transactions (recategorize), Rules, Plan (income sources and budgets), Settings (retention, language, data page, CSV export, delete everything), Demo mode.
- `DemoData`: fixture of a few hundred Swedish-looking transactions over three periods, loaded behind a visible banner.
- Strings in `Localizable.xcstrings`, sv and en.

## Network allowlist: regression guard, not proof

The claim on the data page is scoped to app-process traffic: the app itself talks only to `api.enablebanking.com`. The system browser, during connect, talks to `auth.enablebanking.com`, the bank's hosts and `app.bankid.com`, and the data page lists them. The checks:

1. Unit test: `EnableBankingClient` throws on any host other than `api.enablebanking.com`.
2. Lint test that scans all Swift sources and `Localizable.xcstrings` outside `EnableBankingKit` and fails on `URLSession`, `URLRequest`, `import Network`, `import WebKit`, `contentsOf:`, `AsyncImage`, `NSUserActivity`, `kSecAttrSynchronizable`, and `http` literals, with an explicit allowlist for the handful of links the onboarding guide needs (control panel, repository, privacy page).
3. No `NSAppTransportSecurity` exceptions.
4. User-runnable check documented on the data page and in the README: iOS App Privacy Report lists every domain the app contacted.
5. Manual check before release: device-wide mitmproxy, exercise every screen, compare against the expected-host list above.

## Build order

1. BudgetCore with tests: periods (incl. 2026-12-23, 2027-06-24, 2027-12-23 as banking-day cases), categorizer, reimbursements, dedup, the three numbers, quarterly accrual, CSV. About one session.
2. EnableBankingKit with tests: JWT header and claims against a known key, SPKI PEM export round-trip, URL allowlist, PSU headers, pagination loop with empty pages, decode keeps six fields only. About one session.
3. Flow in the simulator against the Enable Banking sandbox. Needs Carl once: register a sandbox application with the public key the simulator app shows, paste the Application ID back. About five minutes of Carl's time. The sandbox login has no app switch, so the return-in-Safari path is simulated with `xcrun simctl openurl booted "tjugofemte://callback?code=x&state=y"` while the session sheet is up, and the test is that `onOpenURL` completes the flow and dismisses the sheet.
4. App screens, store, demo mode, localization. One to two sessions.
5. Settings, data page, export, delete everything, notifications. One session.
6. Publish the repository with a one-page privacy and terms text on GitHub Pages. Production registration in the control panel asks for a privacy policy URL and a terms URL, so every user needs these to paste; the onboarding guide supplies them.
7. On device with Swedbank. Needs Carl: register a production application with the phone's public key, activate it by linking accounts, run BankID. About fifteen minutes. Then verify dedup across two fetches a day apart.
8. README with setup, architecture, data minimization, store review notes and flags.

Carl's two-minute control panel test, before step 4: in the production environment (not sandbox, the two may validate differently), does the registration form accept `tjugofemte://callback` as a redirect URL?

## Done when

1. Carl's Swedbank account is connected on his phone and transactions are categorized.
2. Budget vs actual and savings target work for the current period, with the explanation line.
3. Delete everything closes the Enable Banking session, then wipes key, Keychain items, database directory, notifications and preferences; CSV export opens in the share sheet.
4. Tests pass; README written.

## Open risks

- Control panel may reject `tjugofemte://callback`. Carl's two-minute test decides. Fallback is HTTPS universal link on the GitHub Pages site that step 6 creates anyway, iOS 17.4 or later for the HTTPS callback, and a disclosure on the data page that GitHub's servers can see the single-use code when the link fails to open the app.
- BankID's exact iOS return behaviour is unverified (bankid.com renders client-side). The two receive paths cover both outcomes; the first on-device run in step 7 is the real test.
- Enable Banking retains PSU IP and user agent in its logs for an unknown period. Stated on the data page.
- RSA-4096 generation on a phone can take several seconds. Measured in step 2; if it does, onboarding shows a one-time progress state.
- The sandbox may not list banks for country SE, only mock banks for certain countries. Checked on the first call in step 3; the country becomes a debug-build setting if needed.
- Swedbank may require personnummer as psu_id for the decoupled BankID flow. Read `auth_methods` from GET /aspsps and prefer the redirect approach. If required, ask at auth time and never store it.
- Swedbank transaction id stability is unknown. The fingerprint fallback covers it; the day-apart fetch test confirms.
- Store review: Apple guideline on highly regulated fields may ask for a legal entity as publisher (from memory, verify). Demo mode plus review notes and the open source link are the mitigation.
- Expo-style over-the-air updates do not exist here, so no phone-home. Apple's own crash reporting is user opt-in and outside the app.
