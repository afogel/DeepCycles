import Foundation

/// "mm:ss" for a countdown. Negative values read as zero.
package func mmss(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%02d:%02d", s / 60, s % 60)
}

package extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }

    /// The nearest multiple of `m` minutes.
    func rounded(toMinutes m: Int) -> Date {
        let interval = TimeInterval(m * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / interval).rounded() * interval)
    }
}

/// The keys days and weeks are stored under: "yyyy-MM-dd" and ISO "yyyy-Www".
package enum DateKeys {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    package static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    package static func date(fromDay key: String) -> Date? { dayFormatter.date(from: key) }

    package static func week(_ date: Date) -> String {
        let c = Calendar(identifier: .iso8601)
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }
}
