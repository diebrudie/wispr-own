import AppKit
import Charts
import SwiftUI

/// Spec 14 — Analytics screen. Every panel answers one question about the
/// user's own dictation history.
///
/// Each measure here is a single series (how much per bucket), so every mark
/// uses one hue — `Theme.chartMark`, whose light and dark steps are checked
/// against the data-viz lightness band and contrast floor. Nothing encodes
/// identity by colour, so there is no categorical palette and no legend: each
/// panel's title names its one series.
struct AnalyticsView: View {
    @ObservedObject var app: AppState

    var body: some View {
        ScrollView {
            AnalyticsContent(analytics: app.analytics)
        }
        .background(Theme.windowBackground)
        .onAppear { app.refreshAnalytics() }
    }
}

/// The layout, over plain data rather than `AppState`, so it can be rendered
/// headlessly — `WisprOwn --snapshot <path>` writes a PNG of this screen with
/// the real history behind it. That's how the layout gets checked; a colour
/// validator can't see label collisions or overflow.
struct AnalyticsContent: View {
    let analytics: HistoryStore.Analytics

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Analytics")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)

            if analytics.isEmpty {
                empty
            } else {
                headline
                Card("Words per day", subtitle: "Last 30 days") {
                    WordsPerDayChart(days: analytics.perDay)
                }
                HStack(alignment: .top, spacing: 20) {
                    Card("When you dictate", subtitle: "Dictations by hour") {
                        ByHourChart(hours: analytics.perHour)
                    }
                    Card("Where it lands", subtitle: "Top apps") {
                        RankedBars(buckets: Array(analytics.perApp.prefix(6)),
                                   total: analytics.dictations,
                                   label: AnalyticsContent.appName)
                    }
                }
                Card("Languages", subtitle: "Share of dictations") {
                    RankedBars(buckets: analytics.perLanguage,
                               total: analytics.dictations,
                               label: AnalyticsContent.languageName)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        Card("Nothing to show yet", subtitle: nil) {
            Text("Dictate a few times and your stats will appear here.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Headline numbers
    //
    // Single values with no trend to read, so these are tiles rather than
    // charts — a bar of one bar says less than the number does.
    private var headline: some View {
        HStack(spacing: 12) {
            Tile(value: AnalyticsContent.decimal(analytics.dictations), unit: "dictations")
            Tile(value: AnalyticsContent.decimal(analytics.words), unit: "words")
            Tile(value: AnalyticsContent.duration(analytics.spokenSeconds), unit: "spent speaking")
            Tile(value: AnalyticsContent.duration(analytics.savedSeconds), unit: "saved vs typing",
                 note: "at \(Int(HistoryStore.typingWordsPerMinute)) wpm")
        }
    }

    // MARK: - Formatting

    /// Bundle IDs are unreadable in a chart, so ask macOS for the real name and
    /// fall back to the last component ("com.apple.Safari" → "Safari").
    static func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    static func languageName(_ code: String) -> String {
        guard code != "unknown" else { return "Unknown" }
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    static func decimal(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    /// "4h 12m" / "12m" / "45s" — always two units at most, so a tile stays scannable.
    static func duration(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let minutes = (seconds % 3600) / 60
            return minutes == 0 ? "\(seconds / 3600)h" : "\(seconds / 3600)h \(minutes)m"
        }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }
}

// MARK: - Charts

/// Magnitude over time → bars on a date axis. Hovering selects a day and shows
/// its exact value; without that the only readable numbers would be the axis.
private struct WordsPerDayChart: View {
    let days: [HistoryStore.Analytics.Day]
    @State private var selected: Date?

    private var selectedDay: HistoryStore.Analytics.Day? {
        guard let selected else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    var body: some View {
        Chart(days) { day in
            BarMark(x: .value("Day", day.date, unit: .day),
                    y: .value("Words", day.words),
                    width: .ratio(0.6)) // thin marks, gap between bars
                .foregroundStyle(Theme.chartMark)
                .cornerRadius(4) // rounded data-end, anchored to the baseline
                .opacity(selectedDay == nil || selectedDay?.id == day.id ? 1 : 0.35)
        }
        .chartXSelection(value: $selected)
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.border); AxisValueLabel() } }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) {
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 190)
        .overlay(alignment: .topLeading) {
            if let day = selectedDay {
                Callout(title: day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                        value: "\(AnalyticsContent.decimal(day.words)) words")
            }
        }
    }
}

private struct ByHourChart: View {
    let hours: [HistoryStore.Analytics.Hour]
    @State private var selected: Int?

    var body: some View {
        Chart(hours) { hour in
            // Fixed width, not .ratio: on a numeric axis Charts has no step size to
            // take a ratio of, and silently draws nothing.
            BarMark(x: .value("Hour", hour.hour),
                    y: .value("Dictations", hour.count),
                    width: .fixed(9))
                .foregroundStyle(Theme.chartMark)
                .cornerRadius(4)
                .opacity(selected == nil || selected == hour.hour ? 1 : 0.35)
        }
        .chartXSelection(value: $selected)
        .chartXScale(domain: -0.5...23.5)
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.border); AxisValueLabel() } }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel { Text(Self.hourLabel(value.as(Int.self) ?? 0)) }
            }
        }
        .frame(height: 190)
        .overlay(alignment: .topLeading) {
            if let selected, let hour = hours.first(where: { $0.hour == selected }), hour.count > 0 {
                Callout(title: Self.hourLabel(selected),
                        value: "\(hour.count) \(hour.count == 1 ? "dictation" : "dictations")")
            }
        }
    }

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

/// Ranked magnitudes with every row named and its value shown — a table that
/// happens to draw its numbers. No colour encodes identity, so the labels do.
private struct RankedBars: View {
    let buckets: [HistoryStore.Analytics.Bucket]
    let total: Int
    let label: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(buckets) { bucket in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(label(bucket.name)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(bucket.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(percent(bucket.count))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.callout)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.chartTrack)
                            Capsule().fill(Theme.chartMark)
                                .frame(width: max(3, geometry.size.width * fraction(bucket.count)))
                        }
                    }
                    .frame(height: 6)
                }
            }
            if buckets.isEmpty {
                Text("No data yet.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func fraction(_ count: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    private func percent(_ count: Int) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((fraction(count) * 100).rounded()))%"
    }
}

// MARK: - Chrome

private struct Callout: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        .padding(6)
        .allowsHitTesting(false)
    }
}

private struct Tile: View {
    let value: String
    let unit: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.accent)
            Text(unit).font(.caption).foregroundStyle(.secondary)
            if let note {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
    }
}

private struct Card<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
    }
}
