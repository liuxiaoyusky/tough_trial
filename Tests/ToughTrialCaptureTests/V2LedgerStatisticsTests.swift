import XCTest
@testable import ToughTrialV2Core

final class V2LedgerStatisticsTests: XCTestCase {
    private let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func testDayProjectionUsesInclusiveStartAndExclusiveEndAndConfirmedCategories() throws {
        let entries = [
            entry(id: "inside-expense", amount: "100", direction: .expense, localDate: "2026-09-16", categoryID: "food"),
            entry(id: "inside-income", amount: "50", direction: .income, localDate: "2026-09-16", categoryID: "salary"),
            entry(id: "before", amount: "9", direction: .expense, localDate: "2026-09-15", categoryID: "food"),
            entry(id: "after", amount: "12", direction: .expense, localDate: "2026-09-17", categoryID: "food")
        ]
        let categories = [
            V2LedgerCategory(id: "others", name: "Others"),
            V2LedgerCategory(id: "food", name: "吃饭"),
            V2LedgerCategory(id: "salary", name: "工资")
        ]

        let projections = V2LedgerStatistics.project(
            entries: entries,
            categories: categories,
            anchor: date("2026-09-16"),
            period: .day,
            calendar: calendar
        )

        XCTAssertEqual(projections.count, 1)
        let projection = try XCTUnwrap(projections.first)
        XCTAssertEqual(projection.totals.income, decimal("50"))
        XCTAssertEqual(projection.totals.expense, decimal("100"))
        XCTAssertEqual(projection.totals.net, decimal("-50"))
        XCTAssertEqual(projection.categoryTotals.map(\.id), ["food", "salary"])
        XCTAssertEqual(projection.dailyTotals.map(\.localDate), ["2026-09-16"])
        XCTAssertEqual(projection.dailyTotals.first?.expense, decimal("100"))
        XCTAssertEqual(projection.unknownDateCount, 0)
    }

    func testNaturalPeriodBoundariesFollowCalendarDayWeekMonthAndYear() throws {
        let entries = [
            entry(id: "day-before", amount: "1", localDate: "2026-03-17"),
            entry(id: "day-inside", amount: "2", localDate: "2026-03-18"),
            entry(id: "day-after", amount: "4", localDate: "2026-03-19"),
            entry(id: "week-before", amount: "8", localDate: "2026-03-15"),
            entry(id: "week-start", amount: "16", localDate: "2026-03-16"),
            entry(id: "week-end", amount: "32", localDate: "2026-03-22"),
            entry(id: "week-after", amount: "64", localDate: "2026-03-23"),
            entry(id: "month-before", amount: "128", localDate: "2026-02-28"),
            entry(id: "month-start", amount: "256", localDate: "2026-03-01"),
            entry(id: "month-end", amount: "512", localDate: "2026-03-31"),
            entry(id: "month-after", amount: "1024", localDate: "2026-04-01"),
            entry(id: "year-before", amount: "2048", localDate: "2025-12-31"),
            entry(id: "year-start", amount: "4096", localDate: "2026-01-01"),
            entry(id: "year-end", amount: "8192", localDate: "2026-12-31"),
            entry(id: "year-after", amount: "16384", localDate: "2027-01-01")
        ]
        let anchor = date("2026-03-18")

        let day = try XCTUnwrap(V2LedgerStatistics.project(
            entries: entries, categories: [], anchor: anchor, period: .day, calendar: calendar
        ).first)
        XCTAssertEqual(day.totals.expense, decimal("2"))

        var nonNaturalCalendar = Calendar(identifier: .buddhist)
        nonNaturalCalendar.locale = Locale(identifier: "en_US")
        nonNaturalCalendar.timeZone = timeZone
        nonNaturalCalendar.firstWeekday = 1
        nonNaturalCalendar.minimumDaysInFirstWeek = 4
        let week = try XCTUnwrap(V2LedgerStatistics.project(
            entries: entries, categories: [], anchor: anchor, period: .week, calendar: nonNaturalCalendar
        ).first)
        XCTAssertEqual(week.totals.expense, decimal("55"))

        let month = try XCTUnwrap(V2LedgerStatistics.project(
            entries: entries, categories: [], anchor: anchor, period: .month, calendar: calendar
        ).first)
        XCTAssertEqual(month.totals.expense, decimal("895"))

        let year = try XCTUnwrap(V2LedgerStatistics.project(
            entries: entries, categories: [], anchor: anchor, period: .year, calendar: calendar
        ).first)
        XCTAssertEqual(year.totals.expense, decimal("14335"))
    }

    func testLeapDayAndYearCrossingWeek() throws {
        let entries = [
            entry(id: "leap", amount: "5", localDate: "2024-02-29"),
            entry(id: "march", amount: "8", localDate: "2024-03-01"),
            entry(id: "dec", amount: "10", localDate: "2025-12-31"),
            entry(id: "jan", amount: "20", localDate: "2026-01-01")
        ]
        let leap = try XCTUnwrap(V2LedgerStatistics.project(entries: entries, categories: [],
            anchor: date("2024-02-29"), period: .month, calendar: calendar).first)
        XCTAssertEqual(leap.totals.expense, decimal("5"))
        let week = try XCTUnwrap(V2LedgerStatistics.project(entries: entries, categories: [],
            anchor: date("2026-01-01"), period: .week, calendar: calendar).first)
        XCTAssertEqual(week.totals.expense, decimal("30"))
    }

    func testCurrenciesStaySeparateAndTransfersDoNotChangeTotals() throws {
        let entries = [
            entry(id: "cny-expense", amount: "20", currency: "cny", localDate: "2026-09-16"),
            entry(id: "cny-income", amount: "8", currency: "CNY", direction: .income, localDate: "2026-09-16"),
            entry(id: "cny-transfer", amount: "9999", currency: "CNY", direction: .transfer, localDate: "2026-09-16"),
            entry(id: "cny-transfer-outside", amount: "777", currency: "CNY", direction: .transfer, localDate: "2026-01-01"),
            entry(id: "usd-expense", amount: "30", currency: "USD", localDate: "2026-09-16"),
            entry(id: "usd-transfer", amount: "8888", currency: "USD", direction: .transfer, localDate: "2026-09-16")
        ]

        let projections = V2LedgerStatistics.project(
            entries: entries,
            categories: [],
            anchor: date("2026-09-16"),
            period: .day,
            calendar: calendar
        )

        XCTAssertEqual(projections.map(\.currency), ["CNY", "USD"])
        let cny = try XCTUnwrap(projections.first { $0.currency == "CNY" })
        XCTAssertEqual(cny.totals.income, decimal("8"))
        XCTAssertEqual(cny.totals.expense, decimal("20"))
        XCTAssertEqual(cny.transferCount, 2)
        let usd = try XCTUnwrap(projections.first { $0.currency == "USD" })
        XCTAssertEqual(usd.totals.income, decimal("0"))
        XCTAssertEqual(usd.totals.expense, decimal("30"))
        XCTAssertEqual(usd.transferCount, 1)
    }

    func testUndatedEntriesAreCountedSeparatelyAndNeverUseRecordedAt() throws {
        let entries = [
            entry(id: "missing-date", amount: "10", localDate: nil, recordedAt: "2026-09-16"),
            entry(id: "invalid-date", amount: "20", localDate: "2026-02-30", recordedAt: "2026-09-16"),
            entry(id: "dated", amount: "7", localDate: "2026-09-16", recordedAt: "2020-01-01"),
            entry(id: "undated-transfer", amount: "900", direction: .transfer, localDate: nil, recordedAt: "2026-09-16")
        ]

        let projection = try XCTUnwrap(V2LedgerStatistics.project(
            entries: entries,
            categories: [],
            anchor: date("2026-09-16"),
            period: .month,
            calendar: calendar
        ).first)

        XCTAssertEqual(projection.totals.expense, decimal("7"))
        XCTAssertEqual(projection.dailyTotals.map(\.localDate), ["2026-09-16"])
        XCTAssertEqual(projection.unknownDateCount, 2)
        XCTAssertEqual(projection.transferCount, 1)
    }

    private func entry(
        id: String,
        amount: String,
        currency: String = "CNY",
        direction: V2LedgerDirection = .expense,
        localDate: String?,
        categoryID: String = "others",
        recordedAt: String = "2026-09-01"
    ) -> V2LedgerEntry {
        V2LedgerEntry(
            id: id,
            amount: amount,
            currency: currency,
            direction: direction,
            text: id,
            localDate: localDate,
            categoryID: categoryID,
            recordedAt: date(recordedAt),
            receiptID: "receipt-\(id)"
        )
    }

    private func date(_ value: String) -> Date {
        guard let date = V2CaptureContract.date(value, timeZone: timeZone) else {
            XCTFail("Invalid fixture date: \(value)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
