import Foundation

/// Days on which Swedish banks settle payments. Salaries due on a non-banking day
/// are paid on the previous banking day, which is what moves a payday period's start.
public enum SwedishBankingDays {
    public static func isBankingDay(_ date: Date) -> Bool {
        let cal = Calendar.stockholm
        let weekday = cal.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return !closedDays(year: c.year!).contains(MonthDay(c.month!, c.day!))
    }

    public static func previousBankingDay(onOrBefore date: Date) -> Date {
        var day = Calendar.stockholm.startOfDay(for: date)
        while !isBankingDay(day) {
            day = Calendar.stockholm.date(byAdding: .day, value: -1, to: day)!
        }
        return day
    }

    struct MonthDay: Hashable {
        let month: Int, day: Int
        init(_ month: Int, _ day: Int) { self.month = month; self.day = day }
        init(_ date: Date) {
            let c = Calendar.stockholm.dateComponents([.month, .day], from: date)
            self.init(c.month!, c.day!)
        }
    }

    /// Public holidays that fall on weekdays plus the eves banks close for
    /// (midsommarafton, julafton, nyårsafton). Saturday-only holidays are omitted.
    static func closedDays(year: Int) -> Set<MonthDay> {
        let cal = Calendar.stockholm
        let easter = easterSunday(year: year)
        func plus(_ days: Int) -> MonthDay { MonthDay(cal.date(byAdding: .day, value: days, to: easter)!) }
        // Midsommarafton is the Friday between 19 and 25 June.
        let june19 = cal.date(from: DateComponents(year: year, month: 6, day: 19))!
        let offsetToFriday = (6 - cal.component(.weekday, from: june19) + 7) % 7
        return [
            MonthDay(1, 1), MonthDay(1, 6), MonthDay(5, 1), MonthDay(6, 6),
            MonthDay(12, 24), MonthDay(12, 25), MonthDay(12, 26), MonthDay(12, 31),
            plus(-2), plus(1), plus(39),  // långfredagen, annandag påsk, Kristi himmelsfärdsdag
            MonthDay(6, 19 + offsetToFriday),
        ]
    }

    /// Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
    static func easterSunday(year: Int) -> Date {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return Calendar.stockholm.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
