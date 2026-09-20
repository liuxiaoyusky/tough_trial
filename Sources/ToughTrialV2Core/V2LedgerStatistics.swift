import Foundation

/// Pure projections for the ledger statistics surface. The projection keeps
/// currencies separate and only uses the entry's explicit `localDate`; an
/// entry without a valid consumption date is reported separately instead of
/// being assigned to its `recordedAt` day.
public enum V2LedgerStatistics {
    public enum Period: String, CaseIterable, Codable, Hashable, Sendable {
        case day
        case week
        case month
        case year

        public var label: String {
            switch self {
            case .day: "日"
            case .week: "周"
            case .month: "月"
            case .year: "年"
            }
        }

        fileprivate var calendarComponent: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }
    }

    public struct Totals: Equatable, Sendable {
        public var income: Decimal
        public var expense: Decimal
        public var net: Decimal { income - expense }

        public init(income: Decimal = .zero, expense: Decimal = .zero) {
            self.income = income
            self.expense = expense
        }

        fileprivate mutating func add(direction: V2LedgerDirection, amount: Decimal) {
            switch direction {
            case .income: income += amount
            case .expense: expense += amount
            case .transfer: break
            }
        }
    }

    public struct CategoryTotal: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let totals: Totals

        public var income: Decimal { totals.income }
        public var expense: Decimal { totals.expense }
        public var net: Decimal { totals.net }

        public init(id: String, name: String, totals: Totals) {
            self.id = id
            self.name = name
            self.totals = totals
        }
    }

    public struct DailyTotal: Identifiable, Equatable, Sendable {
        public let localDate: String
        public let date: Date
        public let totals: Totals

        public var id: String { localDate }
        public var income: Decimal { totals.income }
        public var expense: Decimal { totals.expense }
        public var net: Decimal { totals.net }

        public init(localDate: String, date: Date, totals: Totals) {
            self.localDate = localDate
            self.date = date
            self.totals = totals
        }
    }

    public struct Projection: Identifiable, Equatable, Sendable {
        public let currency: String
        public let period: Period
        public let periodStart: Date
        public let periodEnd: Date
        public let totals: Totals
        /// Only entries whose category resolves to a current, confirmed
        /// category appear here. Entries still assigned to `others` (or to a
        /// missing/merged category) remain represented by `unclassified`.
        public let categoryTotals: [CategoryTotal]
        public let unclassified: Totals
        public let dailyTotals: [DailyTotal]
        /// Transfer entries are intentionally excluded from all amount totals.
        /// The count covers every transfer in this currency, independent of
        /// the selected date period.
        public let transferCount: Int
        /// Entries with no valid `localDate` cannot be assigned to a period.
        /// This count covers every such entry in the currency, independent of
        /// the selected period.
        public let unknownDateCount: Int

        public var id: String { currency }

        public init(
            currency: String,
            period: Period,
            periodStart: Date,
            periodEnd: Date,
            totals: Totals,
            categoryTotals: [CategoryTotal],
            unclassified: Totals,
            dailyTotals: [DailyTotal],
            transferCount: Int,
            unknownDateCount: Int
        ) {
            self.currency = currency
            self.period = period
            self.periodStart = periodStart
            self.periodEnd = periodEnd
            self.totals = totals
            self.categoryTotals = categoryTotals
            self.unclassified = unclassified
            self.dailyTotals = dailyTotals
            self.transferCount = transferCount
            self.unknownDateCount = unknownDateCount
        }
    }

    /// Builds one projection per currency. Date intervals use Gregorian
    /// calendar boundaries in the supplied calendar's time zone; weeks run
    /// Monday through Sunday.
    public static func project(
        entries: [V2LedgerEntry],
        categories: [V2LedgerCategory],
        anchor: Date,
        period: Period,
        calendar: Calendar = .current
    ) -> [Projection] {
        var naturalCalendar = Calendar(identifier: .gregorian)
        naturalCalendar.locale = Locale(identifier: "en_US_POSIX")
        naturalCalendar.timeZone = calendar.timeZone
        naturalCalendar.firstWeekday = 2
        naturalCalendar.minimumDaysInFirstWeek = 1
        guard let interval = naturalCalendar.dateInterval(of: period.calendarComponent, for: anchor) else { return [] }

        var categoriesByID: [String: V2LedgerCategory] = [:]
        for category in categories { categoriesByID[category.id] = category }

        let currencyKeys = Set(entries.map { normalizedCurrency($0.currency) }).sorted()
        return currencyKeys.map { currency in
            makeProjection(
                currency: currency,
                entries: entries.filter { normalizedCurrency($0.currency) == currency },
                categoriesByID: categoriesByID,
                period: period,
                interval: interval,
                timeZone: naturalCalendar.timeZone
            )
        }
    }

    private struct DailyAccumulator {
        let date: Date
        var totals: Totals
    }

    private static func makeProjection(
        currency: String,
        entries: [V2LedgerEntry],
        categoriesByID: [String: V2LedgerCategory],
        period: Period,
        interval: DateInterval,
        timeZone: TimeZone
    ) -> Projection {
        var totals = Totals()
        var categoryAmounts: [String: Totals] = [:]
        var unclassified = Totals()
        var daily: [String: DailyAccumulator] = [:]
        var transferCount = 0
        var unknownDateCount = 0

        for entry in entries {
            guard entry.direction != .transfer else {
                transferCount += 1
                continue
            }

            guard let localDate = entry.localDate,
                  let date = V2CaptureContract.date(localDate, timeZone: timeZone) else {
                unknownDateCount += 1
                continue
            }
            guard date >= interval.start && date < interval.end,
                  let amount = Decimal(string: entry.amount, locale: Locale(identifier: "en_US_POSIX")) else { continue }

            totals.add(direction: entry.direction, amount: amount)

            if let categoryID = confirmedCategoryID(entry.categoryID, categoriesByID: categoriesByID),
               categoriesByID[categoryID] != nil {
                categoryAmounts[categoryID, default: Totals()].add(direction: entry.direction, amount: amount)
            } else {
                unclassified.add(direction: entry.direction, amount: amount)
            }

            var day = daily[localDate] ?? DailyAccumulator(date: date, totals: Totals())
            day.totals.add(direction: entry.direction, amount: amount)
            daily[localDate] = day
        }

        let categoryTotals = categoryAmounts.compactMap { id, values -> CategoryTotal? in
            guard let category = categoriesByID[id] else { return nil }
            return CategoryTotal(id: id, name: category.name, totals: values)
        }.sorted {
            let leftAmount = $0.income + $0.expense
            let rightAmount = $1.income + $1.expense
            if leftAmount != rightAmount { return leftAmount > rightAmount }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        let dailyTotals = daily.map { key, value in
            DailyTotal(localDate: key, date: value.date, totals: value.totals)
        }.sorted { $0.date < $1.date }

        return Projection(
            currency: currency,
            period: period,
            periodStart: interval.start,
            periodEnd: interval.end,
            totals: totals,
            categoryTotals: categoryTotals,
            unclassified: unclassified,
            dailyTotals: dailyTotals,
            transferCount: transferCount,
            unknownDateCount: unknownDateCount
        )
    }

    private static func normalizedCurrency(_ value: String) -> String {
        let currency = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return currency.isEmpty ? "—" : currency
    }

    private static func confirmedCategoryID(
        _ categoryID: String?,
        categoriesByID: [String: V2LedgerCategory]
    ) -> String? {
        guard var id = categoryID, !id.isEmpty else { return nil }
        var visited = Set<String>()
        while let category = categoriesByID[id],
              let mergedIntoID = category.mergedIntoID,
              visited.insert(id).inserted {
            id = mergedIntoID
        }
        guard id != "others",
              let category = categoriesByID[id],
              category.mergedIntoID == nil else { return nil }
        return id
    }
}
