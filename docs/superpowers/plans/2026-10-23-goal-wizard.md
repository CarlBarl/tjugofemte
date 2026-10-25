# Goal wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace "type a budget per category" with a six-step setup that sorts unknown merchants, shows the user their money, and derives budgets from a savings goal with hearts that protect what they care about.

**Architecture:** All arithmetic lives in `BudgetCore` as pure functions with tests: category groups, "usual" amounts, recurring charges, the analysis, the goal planner and the sort candidates. `LocalStore` persists the new preferences in its settings table. `AppModel` assembles inputs from the stored transactions and saves the result as ordinary `Budget` rows, so `BudgetMath` and every existing screen keep working. The SwiftUI screens only render.

**Tech Stack:** Swift 6.2 packages, Swift Testing, GRDB 7, SwiftUI (iOS 18), XcodeGen, `Localizable.xcstrings` (en, sv).

**Spec:** `docs/superpowers/specs/2026-10-23-goal-wizard-design.md` (read it whole first). Mockups with the exact goal math in their script: https://claude.ai/artifact/7sQhgDCPVrgXNrCjxMdCGk, source on disk until the session's scratchpad is cleared.

**Prerequisite:** `docs/superpowers/plans/2026-10-23-bank-data-fixes.md` merged. Its `Settings.fullFetchPending` and corrected counterparty text are used here.

## Global Constraints

- Branch `feature/goal-wizard` from `main` after the fixes PR; one PR at the end.
- Decimal arithmetic everywhere; rounding with `NSDecimalRound` (as `PlanSuggestions.roundUp` does), never Double.
- Every budget step is 50 kr. Cuts round down to 50 kr; the half floor rounds up to 50 kr; usual rounds up to 50 kr and is dropped below 50 kr.
- No cut below half of usual. Needs, fixed wants and Unsorted are never cut by the app. The goal never moves by itself.
- Slider 0 to 50 %, step 1. Default goal: 20 %, or the current savings rate if higher, capped at the reachable rate.
- History window for "usual" and the analysis: complete pay periods on the phone, at most 12.
- No literal colors in screens; new tokens `groupNeed`, `groupWant`, `groupSaving` with dark values `#5b8fd4`, `#c97c3c`, `#3fa577`.
- Every new user-facing string in `Localizable.xcstrings` with en and sv.
- No new network hosts; `./scripts/check-allowlist.sh` passes.
- Package tests green in all three packages after every task that touches them.

## Review Focus

1. No complete period yet (connected today): usual, the analysis and the goal screen use the current period so far and never divide by zero. Pinned in Tasks 3 and 5.
2. No planned income (all income sources switched off): savings rate and goal percent are undefined; the planner returns a plan with `reachablePercent == 0` and the screen asks for income. Pinned in Task 6.
3. Hearted categories that drop out of the input (usual fell below 50 kr) are ignored, not crashed on. Pinned in Task 6.
4. The account switch and Delete everything leave no preferences behind that point at the old account's categories. Pinned in Task 7.
5. A merchant whose text is only a phone number or a reference ("+46766274950", "8242039580402") still gets a keyword that matches itself. Pinned in Task 4.

---

### Task 1: Unsorted, the saving kind and category groups

**Files:**
- Modify: `Packages/BudgetCore/Sources/BudgetCore/Category.swift`
- Modify: `Packages/BudgetCore/Sources/BudgetCore/Categorizer.swift` (fallback, line 31)
- Create: `Packages/BudgetCore/Sources/BudgetCore/CategoryGroups.swift`
- Modify: `Packages/LocalStore/Sources/LocalStore/LocalStore.swift` (migration `v2`)
- Modify: `Tjugofemte/Sources/Views/Shared.swift` (`CategoryInfo`), `Tjugofemte/Sources/Model/DemoData.swift` (drop the savings budget)
- Test: `Packages/BudgetCore/Tests/BudgetCoreTests/CategorizerTests.swift`, new `CategoryGroupsTests.swift`, `BudgetMathTests.swift`, `Packages/LocalStore/Tests/LocalStoreTests/LocalStoreTests.swift`

**Interfaces:**
- Produces: `DefaultCategory.unsorted` (kind `.spending`). `CategoryKind.saving`; `DefaultCategory.savings.kind == .saving`. `public enum CategoryGroup: String, Sendable, Codable { case need, want, saving }`. `public struct CategoryGroups: Equatable, Sendable, Codable { public var overrides: [String: CategoryGroup]; public init(overrides: [String: CategoryGroup] = [:]); public func group(of categoryID: String) -> CategoryGroup? }`, nil for income and transfer.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func defaultGroupsFollowTheSpec() {
    let g = CategoryGroups()
    for id in ["rent", "studentLoan", "insurance", "groceries", "transport", "health"] { #expect(g.group(of: id) == .need) }
    for id in ["takeaway", "streaming", "subscriptions", "gym", "entertainment", "shopping", "unsorted"] { #expect(g.group(of: id) == .want) }
    #expect(g.group(of: "savings") == .saving)
    #expect(g.group(of: "income") == nil)
    #expect(g.group(of: "transfer") == nil)
}
@Test func anOverrideFlipsACategoryButNeverUnsorted() {
    let g = CategoryGroups(overrides: ["groceries": .want, "gym": .need, "unsorted": .need])
    #expect(g.group(of: "groceries") == .want)
    #expect(g.group(of: "gym") == .need)
    #expect(g.group(of: "unsorted") == .want)
}
@Test func moneyOutThatMatchesNoRuleIsUnsorted() {
    #expect(Categorizer(userRules: [], ownAccountIDs: []).categorize(text: "SUSHI YAMA", amount: -120) == "unsorted")
}
@Test func savingsTransfersAreNeitherSpendingNorIncome() { /* BudgetMath.summarize with -2000 "Avanza Bank" (savings): actualSpending term 0, no CategoryLine for savings, leftOverSoFar unchanged by it */ }
@Test func upgradeRemovesTheSavingsBudget() { /* LocalStore: a store opened on a v1 file with a savings budget loads without it */ }
```

Update `CategorizerTests` where it asserts `savings.kind == .spending` and where it expects "shopping" as the fallback.

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/BudgetCore && swift test`, then `cd ../LocalStore && swift test`
Expected: compile errors for the new types, then the assertions above.

- [ ] **Step 3: Implement**

Defaults live in a `static let defaults: [String: CategoryGroup]` in `CategoryGroups`. `BudgetMath` needs no change beyond the kind (its spending filter is `== .spending`); check `PlanSuggestions` for the same. Migration `v2` runs `DELETE FROM budgets WHERE category_id = 'savings'`. In `CategoryInfo`: unsorted is "Unsorted"/"Osorterat" with symbol `questionmark.circle`; "Shopping & other" becomes "Shopping"/"Shopping". Add unsorted to `CategoryInfo.spending`.

- [ ] **Step 4: Run the tests**

Run: `for p in BudgetCore LocalStore; do (cd Packages/$p && swift test 2>&1 | grep -E "Test run|failed"); done`
Expected: both suites pass.

- [ ] **Step 5: Commit**

```bash
git add Packages Tjugofemte
git commit -m "Unsorted category, savings as its own kind, and need/want/saving groups"
```

### Task 2: Usual amounts per category

**Files:**
- Create: `Packages/BudgetCore/Sources/BudgetCore/Usual.swift`
- Test: `Packages/BudgetCore/Tests/BudgetCoreTests/UsualTests.swift`

**Interfaces:**
- Produces: `public struct UsualAmount: Equatable, Sendable { public let amount: Decimal; public let periods: Int }` (periods 0 means "this period so far"). `public enum Usual { public static func perCategory(transactions: [Transaction], rule: PeriodRule, quarterly: [String: Decimal] = [:], today: Date = Date(), maxPeriods: Int = 12) -> [String: UsualAmount] }`, keyed by spending-kind category id.

- [ ] **Step 1: Write the failing tests** (fixtures in the style of `PlanSuggestionsTests`, `today = d(2026, 10, 17)`, payday 25)

```swift
@Test func meanCountsPeriodsWithoutSpendingAsZero() { /* takeaway 600 in Aug, 0 in Sep: usual 300, periods 2 */ }
@Test func roundsUpToFiftyAndDropsBelowFifty() { /* 1 201 -> 1 250; streaming 40 -> absent */ }
@Test func usesAtMostTwelveCompletePeriods() { /* 14 complete periods of data: periods == 12 */ }
@Test func noCompletePeriodUsesThisPeriodSoFar() { /* data only since 2026-09-26: periods == 0, amount = this period's total rounded up */ }
@Test func aQuarterlyCategoryIsAThirdOfItsQuarterlyAmount() {
    let u = Usual.perCategory(transactions: [], rule: rule, quarterly: ["studentLoan": 4_950], today: today)
    #expect(u["studentLoan"] == UsualAmount(amount: 1_650, periods: 0))
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/BudgetCore && swift test --filter UsualTests`
Expected: compile error, `Usual` not defined.

- [ ] **Step 3: Implement `Usual.perCategory`**

Complete periods are the ones before the current period whose start is on or after the earliest transaction, newest first, up to `maxPeriods`. This is `PlanSuggestions.budgets`'s period walk with the cap raised to 12; reuse `PlanSuggestions.roundUp`. A category in `quarterly` always gets `quarterly / 3` rounded up to 50 kr, whatever its transactions say.

- [ ] **Step 4: Run the tests**

Run: `cd Packages/BudgetCore && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/BudgetCore
git commit -m "Usual amount per category over up to twelve complete periods"
```

### Task 3: Recurring charges, fixed wants and the merchant keyword

**Files:**
- Create: `Packages/BudgetCore/Sources/BudgetCore/MerchantKey.swift`, `Packages/BudgetCore/Sources/BudgetCore/RecurringDetector.swift`
- Test: `Packages/BudgetCore/Tests/BudgetCoreTests/MerchantKeyTests.swift`, `RecurringDetectorTests.swift`

**Interfaces:**
- Produces: `public enum MerchantKey { public static func keyword(for counterparty: String) -> String }`. `public struct RecurringCharge: Equatable, Sendable, Identifiable { public enum Cadence: Sendable { case monthly, quarterly }; public let keyword: String; public let name: String; public let categoryID: String; public let amount: Decimal; public let cadence: Cadence; public let lastSeen: Date; public var id: String { keyword }; public var perPeriod: Decimal }`. `public enum RecurringDetector { public static func detect(transactions: [Transaction], excluding: Set<String> = ["rent", "studentLoan"]) -> [RecurringCharge]; public static func fixedCategories(transactions: [Transaction], charges: [RecurringCharge], groups: CategoryGroups, threshold: Decimal = 0.8) -> Set<String> }`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func keywordDropsTrailingWordsWithDigits() {
    #expect(MerchantKey.keyword(for: "PRESSBYRAN 5521") == "pressbyran")
    #expect(MerchantKey.keyword(for: "KLARNA*ZALANDO") == "klarna*zalando")
    #expect(MerchantKey.keyword(for: "  ICA  Nära 12 ") == "ica nära")
}
@Test func aKeywordThatWouldBeEmptyKeepsTheText() {
    #expect(MerchantKey.keyword(for: "+46766274950") == "+46766274950")
}
@Test func everyKeywordMatchesTheTextItCameFrom() {
    for text in ["PRESSBYRAN 5521", "KLARNA*ZALANDO", "+46766274950", "8242039580402", "K*hotels com", "REVOLUT**3590*"] {
        #expect(Categorizer.matches(MerchantKey.keyword(for: text), in: Categorizer.normalize(text)), "\(text)")
    }
}
@Test func threeMonthlyChargesOfAboutTheSameAmountAreRecurring() { /* Netflix 149 on 3 dates 30 days apart: one charge, monthly, perPeriod 149 */ }
@Test func amountsThatDriftMoreThanTenPercentAreNot() { /* 149, 199, 149: none */ }
@Test func twoChargesAboutAQuarterApartAreQuarterly() { /* "FOLKSAM KVARTAL" -4950, category insurance, twice 91 days apart: quarterly, perPeriod 1650 */ }
@Test func rentAndStudentLoanAreLeftOut() { /* monthly rent 10 400 x3: none */ }
@Test func aWantMostlyMadeOfChargesIsFixed() { /* streaming 3 charges = 100 % -> fixed; takeaway with one recurring and many one-offs -> not */ }
```

If `everyKeywordMatchesTheTextItCameFrom` fails for a text whose keyword begins or ends with a non-letter (`+46...`, `revolut**3590*`), make `Categorizer.matches` treat a keyword boundary at a non-letter character as satisfied; add that as a Categorizer test too.

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/BudgetCore && swift test --filter "MerchantKeyTests|RecurringDetectorTests"`
Expected: compile errors.

- [ ] **Step 3: Implement**

Money out only, `kind == .spending`, grouped by `MerchantKey.keyword`. Monthly: at least 3 occurrences with every gap 25 to 35 days and every amount within 10 % of the median. Quarterly: at least 2 with gaps 80 to 100 days, same amount rule. `amount` is the median; `name` is the most recent raw text. A category is fixed when it is in the want group, is not unsorted, and its recurring charges' share of its spending over the same transactions is at least `threshold`.

- [ ] **Step 4: Run the tests**

Run: `cd Packages/BudgetCore && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/BudgetCore
git commit -m "Merchant keyword, recurring charges and fixed wants"
```

### Task 4: Sort candidates

**Files:**
- Create: `Packages/BudgetCore/Sources/BudgetCore/SortStep.swift`
- Test: `Packages/BudgetCore/Tests/BudgetCoreTests/SortStepTests.swift`

**Interfaces:**
- Consumes: `MerchantKey.keyword(for:)` (Task 3).
- Produces: `public struct SortCandidate: Equatable, Sendable, Identifiable { public let keyword: String; public let name: String; public let total: Decimal; public let count: Int; public var id: String { keyword } }`. `public enum SortStep { public static func candidates(transactions: [Transaction], limit: Int = 8) -> [SortCandidate]; public static func sortedShare(transactions: [Transaction]) -> Decimal }` (0 to 1; 1 when there is no spending).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func spellingsOfOneMerchantBecomeOneCandidate() { /* PRESSBYRAN 5521 (-89) and PRESSBYRAN 1234 (-64), unsorted: one candidate "pressbyran", total 153, count 2 */ }
@Test func candidatesAreTheBiggestUnsortedByTotal() { /* 10 unsorted merchants: 8 returned, descending; sorted rows are never candidates */ }
@Test func sortedShareIsSpendingOutsideUnsorted() { /* 900 groceries + 100 unsorted + 2000 savings + 500 transfer: 0.9 */ }
@Test func noSpendingIsFullySorted() { #expect(SortStep.sortedShare(transactions: []) == 1) }
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/BudgetCore && swift test --filter SortStepTests`
Expected: compile error.

- [ ] **Step 3: Implement** (spending kind only; `name` is the most common raw text of the group).

- [ ] **Step 4: Run the tests**

Run: `cd Packages/BudgetCore && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/BudgetCore
git commit -m "Sort step candidates and the sorted share"
```

### Task 5: The analysis and the nudge

**Files:**
- Create: `Packages/BudgetCore/Sources/BudgetCore/SpendingAnalysis.swift`
- Test: `Packages/BudgetCore/Tests/BudgetCoreTests/SpendingAnalysisTests.swift`

**Interfaces:**
- Consumes: `CategoryGroups` (Task 1), `Usual` period walk (Task 2).
- Produces: `public struct WantTrend: Equatable, Sendable { public let categoryID: String; public let perPeriod: Decimal; public let changePercent: Int? }`. `public struct SpendingAnalysis: Equatable, Sendable { public let periods: Int; public let incomePerPeriod: Decimal; public let otherIncomePerPeriod: Decimal; public let needsPerPeriod: Decimal; public let wantsPerPeriod: Decimal; public var savedPerPeriod: Decimal { get }; public var savingsRate: Decimal? { get }; public let topWants: [WantTrend] }` and `public static func analyze(transactions: [Transaction], rule: PeriodRule, groups: CategoryGroups, incomeSources: [IncomeSource], today: Date = Date()) -> SpendingAnalysis`. `public enum GoalNudge { public static func shouldShow(lastComplete: PeriodSummary, plannedIncome: Decimal) -> Bool }`.

- [ ] **Step 1: Write the failing tests**

Build three complete periods with the mockup's monthly numbers: income 34 200 ("Lön"), needs 19 300 (rent 10 400, groceries 4 800, CSN 1 650, transport 1 400, insurance 600, health 450), wants 12 164 (takeaway 3 600, shopping 3 100, entertainment 1 900, unsorted 1 850, subscriptions 790, gym 499, streaming 425), plus a 2 000 savings transfer.

```swift
@Test func ratesTheMockupMonthAtEightPercent() {
    let a = SpendingAnalysis.analyze(transactions: txs, rule: rule, groups: CategoryGroups(), incomeSources: [salary], today: today)
    #expect(a.periods == 3)
    #expect(a.incomePerPeriod == 34_200)
    #expect(a.needsPerPeriod == 19_300)
    #expect(a.wantsPerPeriod == 12_164)
    #expect(a.savedPerPeriod == 2_736)
    #expect(a.savingsRate == Decimal(2_736) / Decimal(34_200))   // the 2 000 transfer is not spending
    #expect(a.topWants.map(\.categoryID) == ["takeaway", "shopping", "entertainment"])
    #expect(a.topWants[0].changePercent == nil)   // fewer than six periods: no trend
}
@Test func swishThatMatchesNoIncomeSourceIsOtherIncome() { /* +1 500 "Swish mottagen Kim" each period: otherIncomePerPeriod 1 500 */ }
@Test func flippingGroceriesMovesItToWants() { /* overrides ["groceries": .want]: needs 14 500, wants 16 964 */ }
@Test func sixPeriodsShowATrend() { /* takeaway 3 000 for three periods then 3 600: changePercent 20 */ }
@Test func noCompletePeriodUsesThisPeriodSoFar() { /* data only since the current period began: periods 0, figures are this period so far, no division by zero */ }
@Test func noIncomeHasNoRate() { #expect(SpendingAnalysis.analyze(transactions: [], rule: rule, groups: CategoryGroups(), incomeSources: [], today: today).savingsRate == nil) }
@Test func nudgeFiresBelowMinusFivePercentOfPlannedIncome() { /* leftOverSoFar -1 711 on 34 200: true; -1 710: false */ }
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/BudgetCore && swift test --filter SpendingAnalysisTests`
Expected: compile error.

- [ ] **Step 3: Implement**

Per-period figures are totals over the complete periods divided by their count; with none, the current period so far (periods 0). Income is income kind; "other" is income not matched by any source's keyword (`Categorizer.matches`, as `BudgetMath` does). Needs and wants come from `groups`; saving and transfer are left out. Trend: with six or more periods, the last three periods' mean against the rest, as a rounded whole percent. The nudge compares `lastComplete.leftOverSoFar.value` with `-plannedIncome * 0.05`.

- [ ] **Step 4: Run the tests**

Run: `cd Packages/BudgetCore && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/BudgetCore
git commit -m "Spending analysis: savings rate, split, biggest wants, and the nudge"
```

### Task 6: The goal planner

**Files:**
- Create: `Packages/BudgetCore/Sources/BudgetCore/GoalPlanner.swift`
- Test: `Packages/BudgetCore/Tests/BudgetCoreTests/GoalPlannerTests.swift`

**Interfaces:**
- Produces: `public struct WantInput: Equatable, Sendable { public let categoryID: String; public let usual: Decimal; public let fixed: Bool }`. `public struct GoalInput: Equatable, Sendable { public let plannedIncome: Decimal; public let needs: [String: Decimal]; public let wants: [WantInput] }` (all per period). `public struct GoalPreferences: Equatable, Sendable, Codable { public var goalPercent: Int; public var hearted: Set<String>; public var amounts: [String: Decimal] }`. `public struct GoalPlan: Equatable, Sendable { public let budgets: [String: Decimal]; public let wantsTotal: Decimal; public let plannedSavings: Decimal; public let reachablePercent: Int; public let reachableMax: Decimal; public let outOfReach: Bool; public let beyondGoal: Bool; public let cutPercent: Int; public let shortfall: Decimal }`. `public enum GoalPlanner` with `plan(_:_:) -> GoalPlan`, `step(_ categoryID: String, by delta: Decimal, input: GoalInput, prefs: GoalPreferences) -> GoalPreferences`, `heart(_ categoryID: String, _ on: Bool, prefs: GoalPreferences) -> GoalPreferences`, `raiseSources(input: GoalInput, prefs: GoalPreferences) -> [RaiseSource]` with `public struct RaiseSource: Equatable, Sendable { public let categoryID: String; public let amount: Decimal }`, `defaultGoal(currentRate: Decimal?, reachablePercent: Int) -> Int`.

The math is the spec's "Goal budgets" section, and the mockup's `plan()` (Goal.dc.html) implements it on the numbers below; the tests pin those numbers, which were checked by running that script.

- [ ] **Step 1: Write the failing tests**

```swift
let input = GoalInput(plannedIncome: 34_200,
    needs: ["rent": 10_400, "groceries": 4_800, "studentLoan": 1_650, "transport": 1_400, "insurance": 600, "health": 450],
    wants: [WantInput(categoryID: "takeaway", usual: 3_600, fixed: false), WantInput(categoryID: "shopping", usual: 3_100, fixed: false),
            WantInput(categoryID: "entertainment", usual: 1_900, fixed: false), WantInput(categoryID: "unsorted", usual: 1_850, fixed: true),
            WantInput(categoryID: "subscriptions", usual: 790, fixed: true), WantInput(categoryID: "gym", usual: 499, fixed: true),
            WantInput(categoryID: "streaming", usual: 425, fixed: true)])
func prefs(_ goal: Int, hearted: Set<String> = [], amounts: [String: Decimal] = [:]) -> GoalPreferences { .init(goalPercent: goal, hearted: hearted, amounts: amounts) }

@Test func twentyPercentTrimsTheFlexibleWants() {
    let p = GoalPlanner.plan(input, prefs(20))
    #expect(p.budgets["takeaway"] == 1_850); #expect(p.budgets["shopping"] == 1_600); #expect(p.budgets["entertainment"] == 950)
    #expect(p.budgets["unsorted"] == 1_850); #expect(p.budgets["streaming"] == 425)
    #expect(p.wantsTotal == 7_964); #expect(p.plannedSavings == 6_936)
    #expect(p.reachablePercent == 20); #expect(!p.outOfReach); #expect(p.cutPercent == 48)
}
@Test func thirtyPercentIsOutOfReachAndShowsTheGap() {
    let p = GoalPlanner.plan(input, prefs(30))
    #expect(p.outOfReach); #expect(p.budgets["takeaway"] == 1_800); #expect(p.budgets["shopping"] == 1_550)
    #expect(p.plannedSavings == 7_036); #expect(p.shortfall == 3_230); #expect(p.reachablePercent == 20)
}
@Test func aRaisedHeartIsPaidByTheOtherWants() {
    let pr = prefs(12, hearted: ["takeaway"], amounts: ["takeaway": 4_100])
    let p = GoalPlanner.plan(input, pr)
    #expect(p.budgets["shopping"] == 1_900); #expect(p.budgets["entertainment"] == 1_150)
    #expect(p.plannedSavings == 4_186); #expect(p.reachablePercent == 13)
    let from = GoalPlanner.raiseSources(input: input, prefs: pr)
    #expect(from.map(\.categoryID) == ["shopping", "entertainment"]); #expect(from.map(\.amount) == [350, 200])
}
@Test func minusStepsFromTheBudgetOnScreen() {
    let next = GoalPlanner.step("shopping", by: -100, input: input, prefs: prefs(20))
    #expect(next.hearted == ["shopping"]); #expect(next.amounts["shopping"] == 1_500)
    #expect(next.goalPercent == 20)   // the goal never moves by itself
}
@Test func plusStepsFromTheBudgetOnScreen() { #expect(GoalPlanner.step("takeaway", by: 100, input: input, prefs: prefs(20)).amounts["takeaway"] == 1_950) }
@Test func fixedWantsOnlyStepDownAndAreNotHearted() { /* step("streaming", by: 100) leaves 425 and no heart; by: -100 gives 325, not hearted */ }
@Test func moreThanTheIncomeIsOutOfReachAtZero() {
    let p = GoalPlanner.plan(input, prefs(5, hearted: ["takeaway", "shopping", "entertainment"], amounts: ["takeaway": 8_000, "shopping": 6_000, "entertainment": 4_000]))
    #expect(p.outOfReach); #expect(p.reachablePercent == 0); #expect(p.reachableMax == -6_664)
}
@Test func zeroGoalKeepsUsualAndSavesBeyondIt() { let p = GoalPlanner.plan(input, prefs(0)); #expect(p.beyondGoal); #expect(p.budgets["takeaway"] == 3_600) }
@Test func noIncomeReachesNothing() { /* plannedIncome 0: reachablePercent 0, outOfReach for any goal above 0, no crash */ }
@Test func aHeartForACategoryNotInTheInputIsIgnored() { /* hearted ["gone"], amounts ["gone": 500]: same plan as prefs(20) */ }
@Test func defaultGoalIsTwentyOrTheCurrentRateCappedAtReachable() {
    #expect(GoalPlanner.defaultGoal(currentRate: 0.08, reachablePercent: 20) == 20)
    #expect(GoalPlanner.defaultGoal(currentRate: 0.27, reachablePercent: 35) == 27)
    #expect(GoalPlanner.defaultGoal(currentRate: 0.08, reachablePercent: 13) == 13)
    #expect(GoalPlanner.defaultGoal(currentRate: nil, reachablePercent: 20) == 20)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/BudgetCore && swift test --filter GoalPlannerTests`
Expected: compile error.

- [ ] **Step 3: Implement**

Follow the spec's formulas. `step` clamps a flexible want to 0 through budget + 5 000 and hearts it; a fixed want clamps to 0 through usual and is not hearted. `heart(on: true)` hearts with no amount (it sits at usual); `heart(on: false)` removes the heart and the amount. `shortfall` is `S - plannedSavings` rounded up to 10 kr when out of reach, else 0. `cutPercent` is `round((1 - max(f, 0.5)) * 100)` when 0 < f < 1, else 0.

- [ ] **Step 4: Run the tests**

Run: `cd Packages/BudgetCore && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/BudgetCore
git commit -m "Goal planner: budgets from a savings goal, hearts and the reachable rate"
```

### Task 7: Store the preferences

**Files:**
- Modify: `Packages/LocalStore/Sources/LocalStore/LocalStore.swift` (`Settings`, `settings()`, `saveSettings(_:)`)
- Test: `Packages/LocalStore/Tests/LocalStoreTests/LocalStoreTests.swift`

**Interfaces:**
- Consumes: `GoalPreferences`, `CategoryGroups` (Codable).
- Produces: `Settings.goal: GoalPreferences?` (key `goal_preferences`, JSON), `Settings.groups: CategoryGroups` (key `group_overrides`), `Settings.goalSetupDone: Bool` (key `goal_setup_done`), `Settings.retentionAsked: Bool` (key `retention_asked`), `Settings.nudgeDismissed: PeriodLabel?` (key `nudge_dismissed`, "yyyy-m").

- [ ] **Step 1: Write the failing tests**

```swift
@Test func goalPreferencesAndGroupsRoundTrip() throws {
    var s = Settings()
    s.goal = GoalPreferences(goalPercent: 20, hearted: ["takeaway"], amounts: ["takeaway": 4_100])
    s.groups = CategoryGroups(overrides: ["groceries": .want])
    s.goalSetupDone = true; s.retentionAsked = true; s.nudgeDismissed = PeriodLabel(year: 2026, month: 11)
    try store.saveSettings(s)
    #expect(try store.settings() == s)
}
@Test func freshSettingsHaveNoGoal() throws { #expect(try store.settings().goal == nil); #expect(try store.settings().goalSetupDone == false) }
```

`wipeEmptiesEveryTable` already covers the settings table; extend it to assert `goal == nil` after a wipe.

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/LocalStore && swift test`
Expected: compile errors.

- [ ] **Step 3: Implement** following the `authorized_accounts` JSON pattern. In `AppModel.switchAccount(to:)`, clear `goal` and `groups` overrides together with the transactions (Review Focus 4).

- [ ] **Step 4: Run the tests**

Run: `cd Packages/LocalStore && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/LocalStore Tjugofemte/Sources/Model/AppModel.swift
git commit -m "Store the savings goal, hearts, group overrides and setup flags"
```

### Task 8: AppModel wiring

**Files:**
- Modify: `Tjugofemte/Sources/Model/AppModel.swift` (Plan setup section)
- Modify: `Tjugofemte/Sources/Model/DemoData.swift`

**Interfaces:**
- Consumes: Tasks 1 to 7.
- Produces on `AppModel`: `func analysis() -> SpendingAnalysis`; `func sortCandidates() -> [SortCandidate]`; `func sortedShare() -> Decimal`; `func file(_ candidate: SortCandidate, as categoryID: String)` (adds `KeywordRule(keyword: candidate.keyword, categoryID:)`, recategorizes); `func goalInput(plannedIncome: Decimal) -> GoalInput`; `func recurringCharges() -> [RecurringCharge]`; `func applyGoalPlan(startDay: Int, incomes: [IncomeSource], input: GoalInput, prefs: GoalPreferences)`; `func chooseRetention(months: Int)`; `var showsGoalCard: Bool`; `var showsNudge: Bool`; `func dismissNudge()`.

- [ ] **Step 1: Implement**

`goalInput` builds needs from `Usual` for need-group categories (an existing quarterly budget passes its amount in `quarterly`), wants from `Usual` for want-group categories, with `fixed` true for `RecurringDetector.fixedCategories` and for unsorted. `applyGoalPlan` writes a `Budget` per need (quarterly cadence kept when it was quarterly) and per want from `GoalPlanner.plan`, removes budgets not in the plan (as `applyPlan` does), stores `prefs`, sets `goalSetupDone` and `planDone`. `chooseRetention` sets `retention`, `retentionAsked`, and sets `fullFetchPending` when the new length is longer, then refreshes. `showsGoalCard` is `isSetUp && !settings.goalSetupDone`; `startDemo()` sets `goalSetupDone = true` unless the launch argument `-demo-upgrade` is present, which is how the upgrade path is checked in the simulator. After the `v2` migration, `AppModel.init` runs `recategorize()` once (settings key `categorizer_version`, set to 2), so unlocked rows that fell back to shopping move to unsorted. `showsNudge` uses `GoalNudge.shouldShow` on the last complete period's summary, only when `goalSetupDone` and `nudgeDismissed != selectedPeriod`. Saving a want budget from the Plan tab (`saveBudget`) hearts it at that amount in `settings.goal`.

`DemoData`: twelve periods instead of three, a quarterly CSN of 4 950, the recurring charges from the mockup's list (Folksam 600, Fitness24Seven 499, Bonnier News 259, Storytel 229, Netflix 149, HBO Max 147, Telia 139, Spotify 129, Apple 99, Google One 29), some unsorted merchants, no savings budget, and takeaway rising in the last three periods so the trend shows.

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project Tjugofemte.xcodeproj -scheme Tjugofemte -destination 'platform=iOS Simulator,name=iPhone 17' build | tail -1`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Tjugofemte
git commit -m "Wire the analysis, sort step and goal planner into the app model"
```

### Task 9: Tokens and the Sort and Your money screens

**Files:**
- Modify: `Tjugofemte/Sources/Design/Tokens.swift` (three group tokens)
- Create: `Tjugofemte/Sources/Views/SortStepView.swift`, `Tjugofemte/Sources/Views/YourMoneyView.swift`
- Modify: `Tjugofemte/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 8's `AppModel` API; existing `Screen`, `ScreenTitle`, `Card`, `RowCard`, `Row`, `SectionLabel`, `Hairline`, `CategoryGlyph`.
- Produces: `struct SortStepView: View` and `struct YourMoneyView: View`, each a step body without its own bottom bar (the setup owns the bar).

- [ ] **Step 1: Pick and validate the light values**

Choose light values for `groupNeed`, `groupWant`, `groupSaving`. Load the dataviz skill and run its `scripts/validate_palette.js` on them with `--mode light --surface "#ffffff"`, and on the dark values (`#5b8fd4,#c97c3c,#3fa577`) with `--mode dark --surface "#1a1f1c"`. Expected: "ALL CHECKS PASS" for both.

- [ ] **Step 2: Build the screens to match the mockup boards "Step 3: Sort" and "Step 4: Your money"**

Sort: progress card from `sortedShare()`; one row per candidate with the chips Rent, Student loan, Savings, Shopping, Takeaway, Groceries and More (More opens the existing category picker without Transfer: a rule cannot make a transfer, because `recategorizeUnlocked` never revisits transfer rows and Undo would strand them); a filed row shows "Filed under X, rule saved" with Undo (deletes the rule). Your money: the four cards, with group colors on marks only and every number in text tokens; the trend line only when `changePercent != nil`; the savings rate card's "How is this calculated?" sheet (existing `ExplanationSheet`) lists matched income, other income (Swish and anything no source matches), needs and wants as separate lines; the "What counts as a need?" chips write `settings.groups`.

- [ ] **Step 3: Build and look**

Run: `xcodebuild ... build | tail -1`, then launch with `-demo` in the simulator and screenshot both screens in English and Swedish (XcodeBuildMCP `build_run_sim`, `screenshot`).
Expected: build succeeds; the screens match the mockup's layout; no truncated Swedish strings.

- [ ] **Step 4: Commit**

```bash
git add Tjugofemte
git commit -m "Sort and Your money steps"
```

### Task 10: The Goal screen, the six-step setup and the retention prompt

**Files:**
- Create: `Tjugofemte/Sources/Views/GoalView.swift`, `Tjugofemte/Sources/Views/RetentionPromptView.swift`
- Modify: `Tjugofemte/Sources/Views/PlanSetupView.swift` (six steps, summary), `Tjugofemte/Sources/Views/StartFlow.swift` (the retention prompt before step 1 while `!retentionAsked`)
- Modify: `Packages/BudgetCore/Sources/BudgetCore/PlanSuggestions.swift` (remove `budgets(...)` and `BudgetSuggestions` once nothing calls them) and its tests
- Modify: `Tjugofemte/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `GoalPlanner`, Task 8's `goalInput`, `applyGoalPlan`, `chooseRetention`.
- Produces: `struct GoalView: View { init(input: GoalInput, prefs: Binding<GoalPreferences>, currentRate: Decimal?, savedBudgets: [String: Decimal]? = nil) }`, used by the setup (no saved budgets) and by the Plan tab (the saved plan). While `savedBudgets` is non-nil and the user has not moved the slider, a heart or a step, the rows show the saved amounts; the first move switches to `GoalPlanner.plan`.

- [ ] **Step 1: Build the Goal screen to match the boards "Step 5: Goal", "Goal at 12 %..." and "Goal at 30 %..."**

Slider bound to `prefs.goalPercent`; markers for "Now" and "Reachable"; the gap banner with "Settle at N %" (hidden when `reachableMax < 0`, with the over-income text instead); want rows calling `GoalPlanner.step` and `heart`; the "comes from" line from `raiseSources`; the needs card with quarterly notes; "Usual means your average over the last N complete periods", N from the input. Accessibility labels as in the mockup's buttons.

- [ ] **Step 2: Rebuild the setup flow**

`PlanSetupView` steps: Payday, Income, Sort, Your money, Goal, Summary, with `StepDots(count: 6)`. The goal seeds from `settings.goal` when present, else `GoalPlanner.defaultGoal`. Summary shows the savings number, planned income, needs, wants "trimmed from X", "Goal N %", and the three biggest changes against usual. `apply()` calls `applyGoalPlan`. The retention prompt ("Keep up to 12 months on this phone?" with the spec's wording) is shown by `StartFlow` before step 1 while `!retentionAsked`, not in the account picker, because `completeSession` picks a lone account and fetches by itself; choosing 12 months sets `fullFetchPending`, so the next fetch reaches back. The upgrade card opens the same prompt when `!retentionAsked`.

- [ ] **Step 3: Walk it in the simulator**

Run: fresh simulator install, `-demo`, step through all six steps in English and in Swedish, screenshot each step; drag the slider to 30 % and check the banner; heart Takeaway and press plus five times and check the "comes from" line.
Expected: every step renders; the numbers on the demo data agree with what `GoalPlanner` returns; the goal never changes unless the slider or "Settle" moves it.

- [ ] **Step 4: Run every package's tests and the lint**

Run: `for p in BudgetCore EnableBankingKit LocalStore; do (cd Packages/$p && swift test 2>&1 | grep -E "Test run|failed"); done; ./scripts/check-allowlist.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages Tjugofemte
git commit -m "Goal screen, six-step setup and the retention prompt"
```

### Task 11: After setup: Overview, Plan tab and the upgrade card

**Files:**
- Modify: `Tjugofemte/Sources/Views/OverviewView.swift` (goal line in the hero card, nudge card, upgrade card), `Tjugofemte/Sources/Views/PlanView.swift` ("Suggest from history" opens `GoalView` in a sheet seeded from the saved plan)
- Modify: `Tjugofemte/Resources/Localizable.xcstrings`

- [ ] **Step 1: Implement**

Hero card line "Goal N %, last period M %" when `settings.goal` exists. Nudge card "Adjust plan?" when `showsNudge`, with dismiss. Upgrade card "Set a savings goal" when `showsGoalCard`; it opens the retention prompt if `!retentionAsked`, then the setup at step 3. The Plan tab's Goal sheet passes the saved budgets as `savedBudgets` with the saved hearts and goal, so it shows the saved plan until the user moves something; Save calls `applyGoalPlan`.

- [ ] **Step 2: Walk it in the simulator**

Run: launch with `-demo-upgrade`; check the upgrade card appears and leads to the retention prompt and then step 3; after finishing, check the hero line; edit a want budget in Plan and reopen the Goal sheet: that want is hearted at the edited amount.
Expected: as described, in English and Swedish.

- [ ] **Step 3: Commit**

```bash
git add Tjugofemte
git commit -m "Goal on Overview, nudge, upgrade card and the Plan tab's goal sheet"
```

### Task 12: Words, docs and the real phone

**Files:**
- Modify: `README.md` (Status, Data minimization: retention up to 12 months, recurring charges computed on the phone), `Tjugofemte/Sources/Views/DataPageView.swift`, `docs/privacy.md`, `docs/PLAN.md` (link the spec, move the household item and "leave a period out of usual" to the backlog)
- Modify: `Tjugofemte/Resources/Localizable.xcstrings` (check every new key has sv)

- [ ] **Step 1: Check the strings**

Run: `python3 -I -c "import json;d=json.load(open('Tjugofemte/Resources/Localizable.xcstrings'));m=[k for k,v in d['strings'].items() if k and 'sv' not in v.get('localizations',{})];print(len(m), m[:20])"`
Expected: `0 []` (or only keys that are deliberately untranslated, such as symbols).

- [ ] **Step 2: Full verification**

Run all package tests, the lint and an app build (commands as in Task 10, Step 4, and Task 8, Step 2).
Expected: all green; paste the "Test run" lines into the PR.

- [ ] **Step 3: Carl's phone** (needs Carl, about ten minutes)

Install on the device, open the upgrade card, choose 12 months, go through Sort with real merchants, check that Your money shows "over N months" with N matching the bank's 90 days, set a goal, finish. Read the database back read-only (as in the fixes plan, Task 4) and count budgets, hearts and rules created. Delete the copy.

- [ ] **Step 4: Commit and open the PR**

```bash
git add README.md docs Tjugofemte
git commit -m "Docs and data page for the goal setup"
```
Open the PR with the test counts, the simulator screenshots and the on-phone counts.
