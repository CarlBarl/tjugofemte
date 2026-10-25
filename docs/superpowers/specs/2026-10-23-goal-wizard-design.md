# Plan setup 2: a savings goal with analysis

Decided with Carl in a grilling session on 2026-10-23, then reviewed by a fresh Fable read the same day. Mockups: the "Tjugofemte plan wizard" design canvas, https://claude.ai/artifact/7sQhgDCPVrgXNrCjxMdCGk (private to Carl). Where the review changed a decision, the section says so.

## Why

Carl, after using the setup: "right now it just asks me to input my budget in boxes as numbers". Today's plan setup (`Tjugofemte/Sources/Views/PlanSetupView.swift`) prefills each category with its average over the last complete periods and asks the user to confirm the number. It hands the user's habits back to them. There is no benchmark, no goal and no sense of what to change.

The app's promise is one number: what to move to savings on payday. The new setup starts from that number. The user picks how much of their income to save, sees how their money actually splits, and the app proposes budgets that reach the goal, cutting where the user cares least.

## Goals

1. The user sees their own money before they plan: savings rate, needs/wants/savings split against 50/30/20, recurring costs, biggest wants.
2. The user sets a savings goal in percent with a slider; budgets are derived from history and the goal, not typed.
3. The user can say what matters to them (heart a category, set its budget) and see live where the money comes from.
4. The plan stays honest: no cut deeper than half of usual spending, needs and fixed charges never cut by the app, an unreachable goal shown as a gap in kronor.

## Non-goals (this round)

- Household budgeting with a partner's accounts. In the backlog in `docs/PLAN.md`; a partner's share stays a plan-only income source.
- Automatic rebalancing between periods.
- Per-category percentage caps as the model ("rent at most 30 %"). 50/30/20 is a benchmark shown, not a rule enforced.
- Yearly recurring charges (cannot be seen twice inside a year of history), a "moved 2 000 of 6 936 kr" savings tracker, and a bulk reimbursement rule for Swish. All cut from v1 by the review.
- Light theme work beyond what the tokens already give.

## Anti-goals

- A wizard that feels like a form. If a screen is mostly empty number boxes, it failed.
- A plan that looks good on day 1 and breaks by day 10 (takeaway cut to zero, Netflix trimmed by a third, the electricity bill trimmed because it sat in Unsorted).
- Silent changes: the app never moves a budget or the goal without the user seeing it happen.
- Weakening the privacy promise beyond what is stated under Data.

## The flow

Six steps, one 56 pt button per screen as today. Steps 1 and 2 are unchanged.

1. **Payday** (as today).
2. **Income** (as today).
3. **Sort** (new). The eight biggest unsorted merchants by total spend over the history on the phone, each with category chips. The chips are Rent, Student loan, Savings, Shopping, Takeaway, Groceries, then More (see Probe results). Transfer is not offered: transfer rows are decided at ingest and never re-sorted, so a rule could not be undone; Savings covers Revolut and sparkonto top-ups. One tap files the merchant and saves a rule (keyword below). A progress line: "89 % of your spending is sorted". Skippable.
4. **Your money** (new). Four insights, no more:
   - Savings rate: "You saved 8 % on average over N months". Its "how is this calculated" lists other income (Swish received and anything not matched to an income source) as its own line, so a month of dinner reimbursements is visible rather than hidden in the rate.
   - Split: two bars, yours above the 50/30/20 benchmark, labelled "Needs 56 %, wants 36 %, savings 8 %". Below, "What counts as a need?" with category chips that flip need/want in one tap.
   - Recurring costs: same merchant, similar amount (within 10 %), monthly or quarterly; a count and a monthly total ("10 charges, 2 279 kr a month"), expandable to the list. Rent and student loan are left out so they do not drown the rest.
   - Biggest wants: top three with monthly average. The rising/falling marker (last three months against the rest) shows only with six or more complete periods.
5. **Goal** (replaces today's budgets step).
   - Hero: the savings slider, 0 to 50 %, step 1, showing percent and kronor per period. Default 20 %, or the user's current rate if higher, capped at the reachable rate. A marker shows the highest reachable rate ("Reachable 23 %"); the current rate is marked too.
   - Wants as rows: icon, name, "usually 3 600 kr", the proposed budget, the change against usual, a heart, minus and plus. Minus and plus step 100 kr from the budget on screen, not from usual, and hearting the row; the hearted budget is stored as an absolute amount in kronor (review fix: stepping from usual made one tap on Shopping jump from 1 850 to 3 000 kr). A heart on its own keeps the category at usual.
   - Fixed wants and Unsorted show "never trimmed" and no heart; minus is available on fixed wants for a user about to cancel a charge.
   - Needs as one collapsed card: total and "kept at your usual". Expandable to rows; a quarterly need shows "a third each period".
   - When a hearted want is above usual, a line under the wants: "Takeaway +500 kr comes from Shopping −250 kr, Entertainment −150 kr".
6. **Summary** (as today, plus the goal). Move to savings on payday, planned income, needs, wants, "Goal 20 %", and the three biggest changes against usual.

## The math

**Usual** (review fix, was undefined). A category's usual is the mean of its per-period totals over the complete periods on the phone, up to 12, with periods that have no spending in the category counted as zero, rounded up to 50 kr, and dropped below 50 kr, as `PlanSuggestions.budgets` does today. Every screen that shows a usual says "based on N periods". With one or two complete periods the numbers are shown with that label and nothing else changes; with none, the current period so far is used, as today.

**Groups.** A new `CategoryGroup`: need, want, saving. Defaults: needs are rent, student loan, insurance, groceries, transport, health; wants are takeaway, streaming, subscriptions, gym, entertainment, shopping, unsorted; saving is the savings category. The user's flips are stored as overrides. Unsorted cannot be flipped.

**Savings** (my call, narrowed by the review). The savings category is neither spending nor income anywhere, the way own-account transfers already are: not in `BudgetMath`'s spending, not in "left over so far", not in a budget. Transfers to savings are how the user moves the target, whether they land in the savings category or are own-account transfers to a sparkonto. An existing budget on the savings category is removed on upgrade.

**Savings rate** over a set of complete periods = (income − spending) / income, where income is income-kind transactions (matched sources and other income), spending is need and want spending, and savings and transfers are excluded from both.

**Fixed wants** (my call). A want category is fixed when recurring charges make up at least 80 % of its spending over the history; tune on real data. In the sample data, subscriptions, gym and streaming are fixed. **Unsorted** is treated as fixed in v1 (review fix): on a real Swedish feed it will hold needs the 60 default rules miss (electricity, phone, broadband, childcare, union fees), so trimming it would cut bills.

**Goal budgets**, per period. Let I = planned income, N = need budgets per period (a quarterly budget counts a third), F = fixed wants and Unsorted at usual, P = hearted wants at their set amounts, H = usual of the remaining wants, S = goal × I.

- Room for the remaining wants U = I − N − F − P − S.
- U ≥ H: they keep their usual; the plan saves more than the goal and the screen says so.
- H/2 ≤ U < H: each is cut by the same factor U/H, rounded down to 50 kr (the remainder goes to savings).
- U < H/2: each sits at half its usual, rounded up to 50 kr; the goal is out of reach.
- Reachable rate = (I − N − F − P − sum of the halves) / I, rounded down to a whole percent, never below 0.

**Out of reach.** Carl, after the review: the goal never moves itself. One behaviour for every cause (slider past the marker, a heart, a raise). The goal stays where the user put it and a banner shows the gap: "To reach 20 % you need 910 kr more each month. Lower a hearted want, lower a need, or settle at 17 %", with a "Settle at 17 %" button. When even 0 % is out of reach, the banner says "Needs and fixed charges are 3 564 kr more than your income" and has no settle button.

The savings target stays what it is today: planned income minus budgets, fixed at period start. The goal is how the budgets are chosen. The goal percent is stored; the Goal screen opened from Plan seeds from the saved budgets, goal and hearts, and recomputes only when the user moves something.

## Data

**History.** Carl, after the review: no totals table. Before the setup's first step (and from the upgrade card for existing installs), the app asks "Keep up to 12 months on this phone?" with the probe's wording below, "Keep 12 months" as the big button and "Keep 3 months" under it. The answer sets the existing retention setting, and the next fetch reaches back that far. It is not placed in the account picker, because a session with one account is chosen and fetched automatically. The analysis runs on whatever transactions are on the phone, so the retention promise ("transactions are trimmed to the length you choose") stays true word for word. On a new install `refresh()` already fetches from the retention cutoff, since the phone holds no transactions. An existing install that raises retention needs one deep fetch back to the new cutoff, because `refresh()` otherwise starts a week before the newest stored transaction (`AppModel.swift`, the `overlap` line). How far back Roslagens Sparbank actually returns history is measured by the probe before build.

**Recurring charges** are recomputed from the transactions on the phone on each fetch; nothing extra is stored.

**Unsorted.** New `DefaultCategory.unsorted`; the categorizer's fallback for money out becomes unsorted instead of shopping. "Shopping & other" is renamed "Shopping". On upgrade, unlocked rows are recategorized, so rows that matched no rule move from shopping to unsorted.

**Sort rule keyword** (review fix, was undefined). The keyword saved for a merchant is its counterparty text lowercased, with trailing words that contain a digit removed: "PRESSBYRAN 5521" gives "pressbyran", "KLARNA*ZALANDO" gives "klarna*zalando". It goes through the existing user-rule mechanism and `recategorize()`. Checked against the real counterparty strings on Carl's phone before build.

## After setup

- The Plan tab gets the same Goal screen ("Suggest from history" opens it).
- Budgets stay fixed between periods until the user changes them.
- Overview hero gets one line: "Goal 20 %, last period 17 %".
- One nudge per period at most (review fix, same intent, one definition): when the last complete period ended with "left over" below −5 % of planned income, Overview shows an "Adjust plan?" card that opens the Goal screen. A quarterly CSN month no longer fires it, because the plan set that money aside.
- A budget edited by hand in the Plan tab counts as hearted at that amount.
- **Upgrade** (review fix). Existing installs (Carl's has `planDone` set) get an Overview card "Set a savings goal" that opens the setup at step 3. It is not forced. Until then the old budgets keep working; Unsorted has no budget, and the card says so.

## Constraints

- No new network hosts; the allowlist lint must still pass.
- All new logic lives in `BudgetCore` as pure, tested functions; the views only render. Decimal arithmetic and `NSDecimalRound` for rounding, never Double.
- Tokens and components from `Tjugofemte/Sources/Design/`; no literal colors in screens. The split bar needs three new tokens, one per group, dark values validated for color-blind separation on the dark card (`#1a1f1c`): needs `#5b8fd4`, wants `#c97c3c`, savings `#3fa577`. Light values still need picking and validating the same way. Labels and values stay in text colors, never the group color.
- Swedish and English strings for everything new.
- Every derived number keeps a "how is this calculated" line, as today.
- Anything new in the database goes into `wipe()` and the account-switch path.

## Left to the builder

The exact recurring-detection thresholds beyond "within 10 %"; animation; the empty states; demo data extended to twelve periods with fixed charges and a quarterly CSN so the new screens have something to show; marker labels that would overlap.

## Decided after the review (Carl, 2026-10-23)

1. The goal never moves itself; out of reach always shows the gap banner.
2. History is a retention choice at connect (12 months offered), no totals table.
3. A probe on Carl's phone before build: how far back the bank returns history, the share of spending that matches no rule, and the real counterparty strings for the rule keyword.

## Probe results (Carl's phone, 2026-10-23)

Measured with throwaway builds, counts only, normal build reinstalled afterwards.

- **History is 90 days.** Any `date_from` older than that returns 422 WRONG_TRANSACTIONS_PERIOD, "No valid consent found". So a first run has two or three complete periods, never a year. The retention prompt therefore reads "Keep up to 12 months on this phone? Your bank gives 90 days at a time, so the analysis grows as months build up", and every "over N months" label is computed, never hardcoded. Untested: whether a fetch in the minutes after a fresh BankID login reaches further.
- **Unrecognized spending is large and holds needs.** On the stored counterparty texts, 54 % of money out (95 936 of 177 028 kr) matches no default rule. 124 distinct merchants; the eight biggest cover 63 % of that, the top 20 cover 75 %. Among the eight biggest are his rent landlord and CSN ("CENTRALA STUDIES..."). This confirms Unsorted is never trimmed, and the Sort chips get Rent and Student loan in the first row: Rent, Student loan, Savings, Shopping, Takeaway, Groceries, More.
- **The sort keyword works on real text.** Lowercase, trailing digit words removed: zero misses across all spellings of the top 20 merchants.
- **His 90 days include a summer trip**, so "usual" from that window runs high. Candidate for the backlog, not v1: leave one period out of "usual".
- **Two bugs in the live app come first**, in their own branch and PR before this work: card purchases are stored under the account holder's own name (the merchant is only in `remittance_information`), and 390 stored payments are stale "transfer" rows that recategorizing never revisits. A third is inferred: Enable Banking error bodies carry a numeric `code` and the reason in `error`, so the expired-session banner never fires. Plan: `docs/superpowers/plans/2026-10-23-bank-data-fixes.md`.

## Verification

- BudgetCore tests for usual, the savings rate, groups and overrides, every branch of the goal math (room above usual, cut range, floor, reachable rate, 0 % out of reach, stepping from the displayed budget), quarterly needs, recurring detection (monthly, quarterly, amount drift), and the sort keyword on real-looking strings.
- Simulator walkthrough of a fresh install in demo mode through all six steps, in Swedish and English, plus an existing install with `planDone` set that gets the upgrade card.
- On Carl's phone: a real first fetch, the history depth noted, the sort step on real merchants.
