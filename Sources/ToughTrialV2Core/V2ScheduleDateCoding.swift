import Foundation

/// Retains submillisecond execution timestamps instead of letting ISO8601DateFormatter round them.
enum V2ScheduleDateCoding {
    static func encode(_ date: Date) -> String {
        let seconds = floor(date.timeIntervalSinceReferenceDate)
        var nanos = Int(((date.timeIntervalSinceReferenceDate - seconds) * 1_000_000_000).rounded())
        var whole = Date(timeIntervalSinceReferenceDate: seconds)
        if nanos == 1_000_000_000 { whole = whole.addingTimeInterval(1); nanos = 0 }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return String(formatter.string(from: whole).dropLast()) + String(format: ".%09dZ", nanos)
    }

    static func decode(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let dot = value.firstIndex(of: ".") else { return formatter.date(from: value) }
        let afterDot = value.index(after: dot)
        let digits = value[afterDot...].prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 9,
              let fraction = Double("0." + digits),
              let whole = formatter.date(from: String(value[..<dot]) + String(value[afterDot...].dropFirst(digits.count))) else { return nil }
        return whole.addingTimeInterval(fraction)
    }
}
