import Testing
import Foundation
@testable import BudgetCore

@Suite struct GoalPlannerTests {
    // The mockup's month: needs 19 300, flexible wants 8 600, fixed wants and Unsorted 3 564.
    let input = GoalInput(plannedIncome: 34_200,
        needs: ["rent": 10_400, "groceries": 4_800, "studentLoan": 1_650, "transport": 1_400, "insurance": 600, "health": 450],
        wants: [WantInput(categoryID: "takeaway", usual: 3_600, fixed: false), WantInput(categoryID: "shopping", usual: 3_100, fixed: false),
                WantInput(categoryID: "entertainment", usual: 1_900, fixed: false), WantInput(categoryID: "unsorted", usual: 1_850, fixed: true),
                WantInput(categoryID: "subscriptions", usual: 790, fixed: true), WantInput(categoryID: "gym", usual: 499, fixed: true),
                WantInput(categoryID: "streaming", usual: 425, fixed: true)])

    func prefs(_ goal: Int, hearted: Set<String> = [], amounts: [String: Decimal] = [:]) -> GoalPreferences {
        .init(goalPercent: goal, hearted: hearted, amounts: amounts)
    }

    @Test func twentyPercentTrimsTheFlexibleWants() {
        let p = GoalPlanner.plan(input, prefs(20))
        #expect(p.budgets["takeaway"] == 1_850); #expect(p.budgets["shopping"] == 1_600); #expect(p.budgets["entertainment"] == 950)
        #expect(p.budgets["unsorted"] == 1_850); #expect(p.budgets["streaming"] == 425)
        #expect(p.wantsTotal == 7_964); #expect(p.plannedSavings == 6_936)
        #expect(p.reachablePercent == 20); #expect(!p.outOfReach); #expect(p.cutPercent == 48)
        #expect(!p.beyondGoal); #expect(p.shortfall == 0)
    }

    @Test func thirtyPercentIsOutOfReachAndShowsTheGap() {
        let p = GoalPlanner.plan(input, prefs(30))
        #expect(p.outOfReach); #expect(p.budgets["takeaway"] == 1_800); #expect(p.budgets["shopping"] == 1_550)
        #expect(p.budgets["entertainment"] == 950); #expect(p.budgets["unsorted"] == 1_850)   // halves; Unsorted untouched
        #expect(p.plannedSavings == 7_036); #expect(p.shortfall == 3_230); #expect(p.reachablePercent == 20)
    }

    @Test func aRaisedHeartIsPaidByTheOtherWants() {
        let pr = prefs(12, hearted: ["takeaway"], amounts: ["takeaway": 4_100])
        let p = GoalPlanner.plan(input, pr)
        #expect(p.budgets["takeaway"] == 4_100)
        #expect(p.budgets["shopping"] == 1_900); #expect(p.budgets["entertainment"] == 1_150)
        #expect(p.plannedSavings == 4_186); #expect(p.reachablePercent == 13)
        let from = GoalPlanner.raiseSources(input: input, prefs: pr)
        #expect(from.map(\.categoryID) == ["shopping", "entertainment"]); #expect(from.map(\.amount) == [350, 200])
    }

    @Test func noRaiseHasNoSources() {
        #expect(GoalPlanner.raiseSources(input: input, prefs: prefs(20)).isEmpty)
        #expect(GoalPlanner.raiseSources(input: input, prefs: prefs(20, hearted: ["takeaway"])).isEmpty)   // a heart alone stays at usual
        // At 15 % the raise puts the goal out of reach (without it Shopping would get 50 kr more), so the gap banner speaks instead.
        let raised = prefs(15, hearted: ["takeaway"], amounts: ["takeaway": 4_100])
        #expect(GoalPlanner.plan(input, raised).outOfReach); #expect(!GoalPlanner.plan(input, prefs(15, hearted: ["takeaway"])).outOfReach)
        #expect(GoalPlanner.raiseSources(input: input, prefs: raised).isEmpty)
    }

    @Test func minusStepsFromTheBudgetOnScreen() {
        let next = GoalPlanner.step("shopping", by: -100, input: input, prefs: prefs(20))
        #expect(next.hearted == ["shopping"]); #expect(next.amounts["shopping"] == 1_500)
        #expect(next.goalPercent == 20)   // the goal never moves by itself
    }

    @Test func plusStepsFromTheBudgetOnScreen() {
        #expect(GoalPlanner.step("takeaway", by: 100, input: input, prefs: prefs(20)).amounts["takeaway"] == 1_950)
    }

    @Test func aStepIsClampedToZeroAndFiveThousandAboveTheBudget() {
        #expect(GoalPlanner.step("takeaway", by: -10_000, input: input, prefs: prefs(20)).amounts["takeaway"] == 0)
        #expect(GoalPlanner.step("takeaway", by: 10_000, input: input, prefs: prefs(20)).amounts["takeaway"] == 6_850)   // 1 850 + 5 000
    }

    @Test func fixedWantsOnlyStepDownAndAreNotHearted() {
        let up = GoalPlanner.step("streaming", by: 100, input: input, prefs: prefs(20))
        #expect(up.hearted.isEmpty); #expect(GoalPlanner.plan(input, up).budgets["streaming"] == 425)
        let down = GoalPlanner.step("streaming", by: -100, input: input, prefs: prefs(20))
        #expect(down.hearted.isEmpty); #expect(down.amounts["streaming"] == 325)
        #expect(GoalPlanner.plan(input, down).budgets["streaming"] == 325)
        let unsorted = GoalPlanner.step("unsorted", by: 100, input: input, prefs: prefs(20))
        #expect(unsorted.hearted.isEmpty); #expect(GoalPlanner.plan(input, unsorted).budgets["unsorted"] == 1_850)
    }

    @Test func aHeartKeepsUsualAndUnheartingDropsTheAmount() {
        let hearted = GoalPlanner.heart("shopping", true, prefs: prefs(20, hearted: ["shopping"], amounts: ["shopping": 1_500]))
        #expect(hearted.hearted == ["shopping"]); #expect(hearted.amounts["shopping"] == nil)
        #expect(GoalPlanner.plan(input, hearted).budgets["shopping"] == 3_100)
        let off = GoalPlanner.heart("shopping", false, prefs: prefs(20, hearted: ["shopping"], amounts: ["shopping": 1_500]))
        #expect(off == prefs(20))
    }

    @Test func moreThanTheIncomeIsOutOfReachAtZero() {
        let p = GoalPlanner.plan(input, prefs(5, hearted: ["takeaway", "shopping", "entertainment"], amounts: ["takeaway": 8_000, "shopping": 6_000, "entertainment": 4_000]))
        #expect(p.outOfReach); #expect(p.reachablePercent == 0); #expect(p.reachableMax == -6_664)
        #expect(p.cutPercent == 0)   // nothing left to trim
    }

    @Test func zeroGoalKeepsUsualAndSavesBeyondIt() {
        let p = GoalPlanner.plan(input, prefs(0))
        #expect(p.beyondGoal); #expect(p.budgets["takeaway"] == 3_600)
        #expect(p.plannedSavings == 2_736); #expect(p.cutPercent == 0); #expect(!p.outOfReach)
    }

    @Test func everyWantHeartedStillSavesBeyondASmallGoal() {
        // Nothing is left to trim (H is 0), and the usual spending saves 2 736 against a goal of 1 710.
        let p = GoalPlanner.plan(input, prefs(5, hearted: ["takeaway", "shopping", "entertainment"]))
        #expect(p.beyondGoal); #expect(!p.outOfReach); #expect(p.plannedSavings == 2_736); #expect(p.reachablePercent == 8)
    }

    @Test func noCutGoesBelowHalfOfUsual() {
        // Room 975 for a 1 950 kr want: the factor is exactly a half, and 975 rounded down would be 950.
        let small = GoalInput(plannedIncome: 10_000, needs: ["rent": 6_525], wants: [WantInput(categoryID: "shopping", usual: 1_950, fixed: false)])
        #expect(GoalPlanner.plan(small, prefs(25)).budgets["shopping"] == 1_000)
        #expect(GoalPlanner.plan(small, prefs(24)).budgets["shopping"] == 1_050)
    }

    @Test func noIncomeReachesNothing() {
        let none = GoalInput(plannedIncome: 0, needs: input.needs, wants: input.wants)
        for goal in [1, 20, 50] {
            let p = GoalPlanner.plan(none, prefs(goal))
            #expect(p.reachablePercent == 0); #expect(p.outOfReach); #expect(p.reachableMax == -27_164)
        }
        let empty = GoalPlanner.plan(GoalInput(plannedIncome: 0, needs: [:], wants: []), prefs(20))
        #expect(empty.reachablePercent == 0); #expect(empty.budgets.isEmpty)
    }

    @Test func aHeartForACategoryNotInTheInputIsIgnored() {
        #expect(GoalPlanner.plan(input, prefs(20, hearted: ["gone"], amounts: ["gone": 500])) == GoalPlanner.plan(input, prefs(20)))
        #expect(GoalPlanner.step("gone", by: 100, input: input, prefs: prefs(20)) == prefs(20))
    }

    @Test func defaultGoalIsTwentyOrTheCurrentRateCappedAtReachable() {
        #expect(GoalPlanner.defaultGoal(currentRate: 0.08, reachablePercent: 20) == 20)
        #expect(GoalPlanner.defaultGoal(currentRate: 0.27, reachablePercent: 35) == 27)
        #expect(GoalPlanner.defaultGoal(currentRate: 0.08, reachablePercent: 13) == 13)
        #expect(GoalPlanner.defaultGoal(currentRate: nil, reachablePercent: 20) == 20)
        #expect(GoalPlanner.defaultGoal(currentRate: Decimal(string: "0.279")!, reachablePercent: 35) == 27)   // rounded down
        #expect(GoalPlanner.defaultGoal(currentRate: 0.62, reachablePercent: 70) == 50)   // the slider ends at 50
    }
}
