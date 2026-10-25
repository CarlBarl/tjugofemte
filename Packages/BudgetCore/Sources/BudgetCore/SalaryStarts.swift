import Foundation

/// Period starts read off the day the salary actually booked. Employers often pay a banking day or two
/// before the payday rule says, and the salary should open the period it pays for.
public enum SalaryStarts {
    /// A booking this many days before or after a period's nominal start opens that period.
    static let daysEarly = 7
    static let daysLate = 5

    /// The salary is the keyed income source with the largest plan. A booking counts once it is at least half of that plan,
    /// so a small refund from the employer does not open a period. Calendar months (`startDay` 1) are left alone.
    public static func detect(transactions: [Transaction], incomeSources: [IncomeSource], startDay: Int) -> [PeriodLabel: Date] {
        guard startDay != 1,
              let salary = incomeSources.filter({ !Categorizer.normalize($0.keyword ?? "").isEmpty }).max(by: { $0.plannedAmount < $1.plannedAmount }),
              let keyword = salary.keyword else { return [:] }
        let cal = Calendar.stockholm
        let nominal = PeriodRule(startDay: startDay)
        var starts: [PeriodLabel: Date] = [:]
        for t in transactions where t.amount > 0 && t.amount >= salary.plannedAmount / 2
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

    /// A start the user picked by hand wins over the detected one for the same period.
    public static func overrides(detected: [PeriodLabel: Date], manual: [PeriodLabel: Date]) -> [PeriodLabel: Date] {
        detected.merging(manual) { _, manual in manual }
    }
}
