import Foundation

/// Period starts read off the day the salary actually booked. Employers often pay a banking day or two
/// before the payday rule says, and the salary should open the period it pays for.
public enum SalaryStarts {
    /// A booking this many days before or after a period's nominal start opens that period.
    static let daysEarly = 7
    static let daysLate = 5

    /// The salary is the keyed income source with the largest plan, and nothing is detected when a bigger source has no
    /// keyword, so a small keyed Swish source never opens periods. A booking counts when it is categorized as income, as
    /// BudgetMath counts it, and is at least half of that plan, so a small refund from the employer does not open a period.
    /// Calendar months (`startDay` 1) are left alone.
    public static func detect(transactions: [Transaction], incomeSources: [IncomeSource], startDay: Int) -> [PeriodLabel: Date] {
        guard startDay != 1,
              let salary = incomeSources.filter({ !Categorizer.normalize($0.keyword ?? "").isEmpty }).max(by: { $0.plannedAmount < $1.plannedAmount }),
              let keyword = salary.keyword,
              !incomeSources.contains(where: { $0.plannedAmount > salary.plannedAmount }) else { return [:] }
        let cal = Calendar.stockholm
        let nominal = PeriodRule(startDay: startDay)
        var starts: [PeriodLabel: Date] = [:]
        for t in transactions where categoryKind(t.categoryID) == .income && t.amount > 0 && t.amount >= salary.plannedAmount / 2
            && Categorizer.matches(keyword, in: Categorizer.normalize(t.counterparty)) {
            let day = cal.startOfDay(for: t.bookingDate)
            let c = cal.dateComponents([.year, .month], from: day)
            let guess = PeriodLabel(year: c.year!, month: c.month!)
            for label in [guess.previous, guess, guess.next, guess.next.next] {
                let start = nominal.period(labeled: label).start
                guard day >= cal.date(byAdding: .day, value: -daysEarly, to: start)!,
                      day <= cal.date(byAdding: .day, value: daysLate, to: start)! else { continue }
                starts[label] = min(starts[label] ?? day, day)
            }
        }
        return starts
    }

    /// A start the user picked by hand wins over the detected one for the same period. A detected start on or before
    /// the previous period's start is dropped, so a manual start cannot leave a period empty or inverted.
    static func overrides(detected: [PeriodLabel: Date], manual: [PeriodLabel: Date], startDay: Int) -> [PeriodLabel: Date] {
        var merged = manual
        for (label, start) in detected.sorted(by: { $0.key < $1.key }) where manual[label] == nil {
            let previous = PeriodRule(startDay: startDay, overrides: merged).period(labeled: label.previous).start
            if start > previous { merged[label] = start }
        }
        return merged
    }
}

extension PeriodRule {
    /// The rule the app runs on: payday, the salary's real booking days on top, and manual starts on top of those.
    public static func resolved(startDay: Int, manual: [PeriodLabel: Date], transactions: [Transaction], incomeSources: [IncomeSource]) -> PeriodRule {
        let detected = SalaryStarts.detect(transactions: transactions, incomeSources: incomeSources, startDay: startDay)
        return PeriodRule(startDay: startDay, overrides: SalaryStarts.overrides(detected: detected, manual: manual, startDay: startDay))
    }
}
