import Foundation

let stockholm = Calendar.stockholm

/// Midnight in Europe/Stockholm for the given civil date.
func d(_ year: Int, _ month: Int, _ day: Int) -> Date {
    stockholm.date(from: DateComponents(year: year, month: month, day: day))!
}
