import Testing
import Foundation
@testable import BudgetCore

@Suite struct SwedishBankingDaysTests {
    @Test func weekdaysAreBankingDays() {
        #expect(SwedishBankingDays.isBankingDay(d(2026, 11, 25)))  // Wednesday
    }

    @Test func weekendsAreNot() {
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 10, 25)))  // Sunday
    }

    @Test func fixedHolidaysAreNot() {
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 1, 1)))
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 1, 6)))
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 5, 1)))
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 6, 6)))
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 12, 25)))
        #expect(SwedishBankingDays.isBankingDay(d(2026, 12, 28)))   // Monday after Christmas: Sweden does not move holidays
    }

    @Test func bankClosedEvesAreNot() {
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 12, 24)))  // julafton, Thursday
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 12, 31)))  // nyårsafton, Thursday
        #expect(!SwedishBankingDays.isBankingDay(d(2027, 6, 25)))   // midsommarafton, Friday
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 6, 19)))   // midsommarafton, Friday
    }

    @Test func easterDerivedHolidaysAreNot() {
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 4, 3)))    // långfredagen
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 4, 6)))    // annandag påsk
        #expect(!SwedishBankingDays.isBankingDay(d(2026, 5, 14)))   // Kristi himmelsfärdsdag
        #expect(!SwedishBankingDays.isBankingDay(d(2017, 5, 25)))   // Kristi himmelsfärdsdag 2017
    }

    @Test func previousBankingDaySkipsEvesAndWeekends() {
        #expect(SwedishBankingDays.previousBankingDay(onOrBefore: d(2026, 12, 25)) == d(2026, 12, 23))
        #expect(SwedishBankingDays.previousBankingDay(onOrBefore: d(2027, 6, 25)) == d(2027, 6, 24))
        #expect(SwedishBankingDays.previousBankingDay(onOrBefore: d(2027, 12, 25)) == d(2027, 12, 23))
        #expect(SwedishBankingDays.previousBankingDay(onOrBefore: d(2026, 10, 25)) == d(2026, 10, 23))
        #expect(SwedishBankingDays.previousBankingDay(onOrBefore: d(2026, 11, 25)) == d(2026, 11, 25))
    }
}
