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

## Refinement pass (2026-10-17 evening): Sabel's recipe

Carl: "amazing UI, amazing setup, super easy to use, powerful but not complicated, setup guides the user to plan a budget, set income. Take inspiration from Sabel, as simple, so people actually use it." Sabel (repo `decide`, `App/Decide/Design/Tokens.swift`, `Components.swift`, `Screens/StartFlow.swift`) is dark only, warm near-black, one accent, cards with a 6 % hairline and 16 pt radius, big rounded monospaced numbers, uppercase letter-spaced section labels, one 56 pt button per screen, a full-screen start flow until the app has something to show, and numbers prefilled for the user to confirm rather than type.

### What changes

1. **Design tokens and components** (`Tjugofemte/Sources/Design/`). Dark only, like Sabel. Tjugofemte's own palette: ink `#111413`, card `#1a1f1c`, accent mint `#9fd6b2`, text `#edf0ec`, muted `#a4aca6`, dim `#8e968f`, pill `#252b27`, on-accent `#0f1412`, over-budget coral `#e9967f`. Components: `Card`, `SectionLabel`, `BigButton`, `AmountField` (pill, number pad, Done toolbar), `StatTile`, `Row`. Nothing in a screen writes a literal color.
2. **Start flow before the tabs.** `RootView` shows `StartFlow` until the app is set up (demo, or bank connected and plan done). Welcome screen: the promise in one line, "Connect my bank" (big) and "Try with sample data". The bank wizard stays (five steps, restyled). Then, new, the **plan setup**, prefilled from the fetched transactions:
   - **Payday**: suggested from the biggest recurring deposit's latest day of month; the period dates shown underneath.
   - **Income**: detected recurring deposits (grouped by counterparty, median per period, ≥ 1 000 kr), each with name, amount and keyword, switchable off; "Add income" for plan-only sources.
   - **Budgets**: one row per spending category seen in the last three complete periods, prefilled with the average rounded up to 50 kr, "based on N periods"; categories with no history under "More".
   - **Summary**: income − budgets = savings target, in words, and one button: "Start my budget". Skip is allowed; the Overview then shows a "Plan your budget" card.
   Quarterly cadence stays in the Plan tab editor; the setup keeps every budget monthly.
3. **Overview**: period strip with chevrons, hero card with the savings target as the one big number and "How?" opening the explanation sheet, a "So far" card with left over, received, spent and days left, then budget rows with bars, then income. Reauth as a banner card.
4. **Plan, Settings, Transactions** restyled with the same cards and rows; Plan gets "Suggest from history" which reruns the setup.
5. **BudgetCore `PlanSuggestions`** (pure, tested first): `incomes`, `budgets`, `payday`, `roundUp`.
6. `Settings.planDone` in LocalStore so an existing install (Carl's) is taken through the plan setup once.

### Why this, not that

- Dark only: one palette to get right, and it is the look Carl already uses daily. A light theme can be added through the tokens later.
- Prefill over wizard questions: the bank data is already on the phone; asking the user to type what the app can see is the kind of friction that makes people stop using a budget app.
- Four tabs kept: Overview is the daily screen, Plan is where the numbers live, Transactions is the proof, Settings holds the bank and the data controls. Merging Plan into Settings would hide the one thing people need to adjust.
- Suggestions use complete periods only, median for income and mean for spending: income is one deposit per period and a missing one would halve a mean; spending varies and the mean is what a budget should cover.

### Verification

Package tests for `PlanSuggestions`; simulator run of a fresh install (welcome → demo → plan setup prefilled from demo data → overview), of an existing install that lands in plan setup, and of Swedish; allowlist lint; install on Carl's phone.

## Goal setup (2026-10-23)

The Budgets step of the plan setup above is replaced by three steps, so the setup has six: payday, income, sort the biggest merchants no rule recognized, the user's own money against 50/30/20, a savings goal the budgets follow from, and the summary. A history prompt (keep up to 12 months, or 3) comes before the first step, and installs set up before it get a "Set a savings goal" card on Overview. Design and decisions: [the spec](superpowers/specs/2026-10-23-goal-wizard-design.md). Build order: [the plan](superpowers/plans/2026-10-23-goal-wizard.md), written before the build; where the two differ, the code is what shipped.

## Backlog

- **Household budget (Carl and partner), deferred 2026-10-23.** Carl wants to connect his girlfriend's account too. Kept out of the wizard rework. What it involves, as found in the code that day: the app holds one Enable Banking session and one `selectedAccountUID`, so a combined budget needs a second consent and a budget across sessions; transfers and Swish between the two people must count as internal, not income or spending; shared versus personal costs need a split. Open: whether Enable Banking's personal-use terms and restricted-mode activation allow a partner to link her accounts into Carl's registered application (unverified), and whether she needs her own view, which on two phones would mean sync and break the no-server promise. Until then a partner's share stays a plan-only income source.
- **Done in #2. Fingerprint keys merge real repeat payments, found 2026-10-25.** Two identical payments on one day to the same merchant get the same fingerprint key, and the second is dropped. The full-window fetch on Carl's phone came back with `entry_reference` on every row and brought back 8 September payments the old rows had merged (13 same-day, same-amount, same-counterparty pairs in all, on 7 Sep, 21 Sep and 21 Oct). Carl confirmed the 21 Oct pair in his bank app; the September ones are unchecked. The rows stored on 10-17 had no reference at all, for a reason not found. If a later fetch omits it again, the fingerprint fallback drops repeats again. Open: add an occurrence count to the fingerprint when the bank gives no reference. Fixed that way in #2. Left open there: if a bank sends the same row twice in one fetch without a reference, both are kept, and repeats merged before the fix come back only within the 7-day refresh overlap.
- **Done in #3. The pay period starts after the salary books, found 2026-10-25.** With start day 25 and the 25th on a Sunday, the period began Friday 23 Oct, but the salary booked Thursday 22 Oct (September: Thursday 24th for a Friday 25th). The salary lands in the previous period, while the new one still subtracts the savings target, so Overview showed almost nothing received and a large negative "left over". The period start should follow when the salary actually books. Fixed in #3. Left open there: setting today's period start to a date after today moves the screen to the previous period, and a manual start on a later period can still leave the current one empty, because manual starts always win.
- **Rent and student loan land in "Shopping & other", found 2026-10-23.** The default rent rule looks for "hyra", which a landlord's bankgiro text rarely contains. Covered by the goal setup's Sort step in #4; until that merges, "Always put it here" on the category sheet fixes it per merchant.
- **Done in #5. Header labels draw under the status bar, found 2026-10-25.** "Step 3 of 4" on the plan setup and the day header on the category sheet overlap the clock. Left open in #5: not run on iOS 18.
- **Skipping the plan setup leaves no way back to guidance, found 2026-10-25.** After "Skip for now" nothing prompts the user to set budgets. The goal setup's "Set a savings goal" card on Overview covers it, in #4.
- **Leave a period out of usual, found 2026-10-23.** A one-off period, such as a summer trip, inflates "usual" for every category it touched, and with the bank's 90 days of history (two or three complete periods) it weighs a third to a half of the average. Candidate: let the user leave one period out.
- **Quarterly charges in the goal setup, left open in #4.** A student loan paid once a quarter is recognized as quarterly only after two charges, so with 90 days of history a first run plans it at its average until the second charge is on the phone. A need category that mixes a quarterly charge with monthly spending becomes one quarterly budget. A quarterly need is planned at a third rounded up to 50 kr, so it can sit up to 50 kr above an exact third. Quarterly want budgets become monthly when a goal plan is applied.
- **The "Adjust plan?" nudge, left open in #4.** It adds back quarterly spending above the third set aside, but not the other way: in a month without the quarterly charge, the unspent third still counts as left over, so the nudge is more lenient in those months. A dismissed nudge is compared with the period on screen, so it comes back when the user moves to another period.
- **Smaller things in the goal setup, left open in #4.** The split legend rounds each percent on its own, so the three can add up to 99 or 101. A Sort rule keyword drops only trailing words that contain a digit, so a bankgiro text with its reference number in the middle keeps the number; if that number changes every month, the rule stops matching. To check on a real account.
- **Untested live (from Status):** the consent reminder notification and the cold-start BankID callback.
- **App Store submission, not started.** Apple may ask for a legal entity as publisher for a finance app (see Open risks).
