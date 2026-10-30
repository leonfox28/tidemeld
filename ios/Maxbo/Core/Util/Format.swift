import Foundation
import os

private let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

/// Parses Weibo's `created_at`, e.g. `Mon Oct 12 13:17:46 +0800 2026`; nil if it
/// has another format.
func parseWeiboDate(_ value: String?) -> Date? {
    guard let parts = value?.trimmingCharacters(in: .whitespaces).split(separator: " "),
        parts.count == 6,
        let month = months.firstIndex(of: String(parts[1])),
        let day = Int(parts[2]), let year = Int(parts[5])
    else { return nil }
    let time = parts[3].split(separator: ":").compactMap { Int($0) }
    let offset = parts[4]
    guard time.count == 3, offset.count == 5,
        let offsetHours = Int(offset.dropFirst().prefix(2)),
        let offsetMinutes = Int(offset.suffix(2))
    else { return nil }
    let sign = offset.first == "-" ? -1 : 1
    var components = DateComponents()
    components.year = year
    components.month = month + 1
    components.day = day
    components.hour = time[0]
    components.minute = time[1]
    components.second = time[2]
    components.timeZone = TimeZone(secondsFromGMT: sign * (offsetHours * 3600 + offsetMinutes * 60))
    return Calendar(identifier: .gregorian).date(from: components)
}

/// A post time the way Weibo shows it: relative when recent, a date when not.
func formatPostTime(_ time: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    let seconds = now.timeIntervalSince(time)
    if seconds < 60 { return "刚刚" }
    if seconds < 3600 { return "\(Int(seconds / 60))分钟前" }
    let today = calendar.startOfDay(for: now)
    if time >= today { return "\(Int(seconds / 3600))小时前" }
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time)
    let hm = "\(two(c.hour!)):\(two(c.minute!))"
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), time >= yesterday {
        return "昨天 \(hm)"
    }
    if c.year == calendar.component(.year, from: today) {
        return "\(two(c.month!))-\(two(c.day!)) \(hm)"
    }
    return "\(c.year!)-\(two(c.month!))-\(two(c.day!))"
}

/// A count in Chinese units, rounded down so it never overstates: 9999, 1.2万, 3亿.
func formatCount<N: BinaryInteger>(_ count: N) -> String {
    let count = Int64(count)
    func scaled(_ unit: Int64, _ suffix: String) -> String {
        let tenths = count * 10 / unit
        let whole = tenths / 10
        let fraction = tenths % 10
        return (fraction == 0 || whole >= 100 ? "\(whole)" : "\(whole).\(fraction)") + suffix
    }
    if count < 10_000 { return "\(count)" }
    if count < 100_000_000 { return scaled(10_000, "万") }
    return scaled(100_000_000, "亿")
}

/// Seconds as `m:ss`, or `h:mm:ss` from an hour up.
func formatDuration(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = seconds % 3600 / 60
    let s = two(seconds % 60)
    return h > 0 ? "\(h):\(two(m)):\(s)" : "\(m):\(s)"
}

/// A byte size in MB from below 1 GB, else in GB: `0 MB`, `2.5 MB`, `300 MB`, `1 GB`.
func formatBytes(_ bytes: Int64) -> String {
    let mb = 1024.0 * 1024
    func trim(_ v: Double) -> String {
        v == v.rounded() || v >= 10 ? "\(Int64(v.rounded()))" : String(format: "%.1f", v)
    }
    if Double(bytes) >= 1024 * mb { return "\(trim(Double(bytes) / (1024 * mb))) GB" }
    return "\(trim(Double(bytes) / mb)) MB"
}

private func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

private let logger = Logger(subsystem: "io.github.leonfox28.maxbo", category: "maxbo")

/// Logs [message] in debug builds only. Never log cookie values or post text.
func devLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    let text = message()
    logger.debug("\(text, privacy: .public)")
    #endif
}
