import AppKit
import Charts
import SwiftUI

/// Spec 14 — Insights screen. Every panel answers one question about the
/// user's own dictation history.
///
/// Each measure is a single series (how much per bucket), so marks use one hue —
/// `Theme.chartMark` for bars, `Theme.calendarSteps` for the activity calendar's
/// four intensity steps. Both were run through the data-viz validator (lightness
/// band and contrast for marks; monotone lightness, step gaps and a visible
/// faintest step for the ramp). Nothing encodes identity by colour, so no panel
/// needs a legend — the titles name their series.
struct InsightsView: View {
    @ObservedObject var app: AppState

    var body: some View {
        ScrollView {
            InsightsContent(analytics: app.analytics)
        }
        .background(Color.clear)
        .onAppear { app.refreshAnalytics() }
    }
}

/// The layout, over plain data rather than `AppState`, so it can be rendered
/// headlessly — `WisprOwn --snapshot <path>` writes a PNG of this screen with
/// the real history behind it. That's how the layout gets checked; a colour
/// validator can't see label collisions or overflow.
struct InsightsContent: View {
    let analytics: HistoryStore.Analytics

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Insights")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            if analytics.isEmpty {
                empty
            } else {
                headline
                Card("Words per day", subtitle: "Last 30 days") {
                    WordsPerDayChart(days: analytics.perDay)
                }
                // Both cards take the height of the taller one, so a row reads
                // as a row rather than two cards that happen to be adjacent.
                HStack(alignment: .top, spacing: 20) {
                    Card("When you dictate", subtitle: "Dictations by hour", stretch: true) {
                        ByHourChart(hours: analytics.perHour)
                    }
                    Card("Where it lands", subtitle: "Top apps", stretch: true) {
                        RankedBars(buckets: Array(analytics.perApp.prefix(6)),
                                   total: analytics.dictations,
                                   label: InsightsContent.appName,
                                   icon: InsightsContent.appIcon)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                // Side by side when there's room, stacked when there isn't.
                // Full-bleed cards make the eye travel the whole window for
                // one short row of information.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) { streakCard; languagesCard }
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 20) { streakCard; languagesCard }
                }
            }
        }
        .padding(24)
        .pageWidth()
    }

    private var streakCard: some View {
        Card("\(analytics.currentStreak) day streak",
             subtitle: "Longest run: \(analytics.longestStreak) days",
             titleSize: 22, stretch: true) {
            ActivityCalendar(days: analytics.calendar)
        }
    }

    private var languagesCard: some View {
        Card("Languages", subtitle: "Share of dictations", stretch: true) {
            RankedBars(buckets: analytics.perLanguage,
                       total: analytics.dictations,
                       label: InsightsContent.languageName)
        }
    }

    private var empty: some View {
        Card("Nothing to show yet", subtitle: nil) {
            Text("Dictate a few times and your stats will appear here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Headline row
    //
    // `fixedSize(vertical:)` makes the row adopt its tallest card, and each
    // card's shell fills that height — so the three stay level however much
    // any one of them has to say.
    private var headline: some View {
        HStack(alignment: .top, spacing: 14) {
            SpeedCard(wordsPerMinute: analytics.wordsPerMinute,
                      multiple: analytics.speedMultiple)
            StatCard(value: Self.decimal(analytics.words),
                     caption: "words dictated",
                     trend: analytics.trendPercent,
                     rows: ["\(Self.decimal(analytics.dictations)) dictations",
                            "\(analytics.averageWords) words each"])
            StatCard(value: Self.duration(analytics.savedSeconds),
                     caption: "saved vs typing",
                     trend: nil,
                     rows: ["\(Self.duration(analytics.spokenSeconds)) spent speaking",
                            "typing measured at \(Int(HistoryStore.typingWordsPerMinute)) wpm"])
        }
        .fixedSize(horizontal: false, vertical: true)
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

    /// The app's own icon, straight from macOS — real logos, nothing to ship,
    /// and correct for whatever the user happens to dictate into.
    static func appIcon(_ bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func languageName(_ code: String) -> String {
        guard code != "unknown" else { return "Unknown" }
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    static func decimal(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    /// "4h 12m" / "12m" / "45s" — two units at most, so a card stays scannable.
    static func duration(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let minutes = (seconds % 3600) / 60
            return minutes == 0 ? "\(seconds / 3600)h" : "\(seconds / 3600)h \(minutes)m"
        }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }
}

// MARK: - Headline cards

/// Speaking pace as an arc. The arc is a proportion of a 200 wpm ceiling — fast
/// conversational speech — and the multiple underneath is the part that actually
/// means something: this user's speaking pace over their own typing speed.
private struct SpeedCard: View {
    let wordsPerMinute: Int
    let multiple: Double

    private var fraction: Double { min(1, Double(wordsPerMinute) / 200) }

    var body: some View {
        CardShell(stretch: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(wordsPerMinute)")
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Text("words per minute")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                HStack(spacing: 12) {
                    Gauge(fraction: fraction)
                        .frame(width: 76, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%.1f×", multiple))
                            .font(.title3.weight(.semibold).monospacedDigit())
                        Text("faster than typing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Half-circle arc: recessive track, one filled mark, round caps.
private struct Gauge: View {
    let fraction: Double

    var body: some View {
        ZStack {
            HalfCircle(portion: 1)
                .stroke(Theme.chartTrack, style: .init(lineWidth: 9, lineCap: .round))
            HalfCircle(portion: max(0.02, fraction))
                .stroke(Theme.chartMark, style: .init(lineWidth: 9, lineCap: .round))
        }
        .padding(5)
    }
}

/// Drawn as a real arc rather than a trimmed-and-scaled `Circle` — scaling a
/// stroked shape squashes the stroke with it, which turns the gauge into a blob.
private struct HalfCircle: Shape {
    let portion: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height)
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY),
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(180 + 180 * portion),
                    clockwise: false)
        return path
    }
}

/// A big number, an optional trend pill, and supporting rows under a divider.
private struct StatCard: View {
    let value: String
    let caption: String
    let trend: Int?
    let rows: [String]

    var body: some View {
        CardShell(stretch: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(value)
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Spacer(minLength: 8)
                    if let trend { TrendPill(percent: trend) }
                }
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Divider()
                ForEach(rows, id: \.self) { row in
                    Text(row)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Direction is carried by the arrow and the sign, not by colour alone.
private struct TrendPill: View {
    let percent: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: percent >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold))
            Text("\(abs(percent))%")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.tintedFill, in: Capsule())
        .help("Compared with the previous 30 days")
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
        .chartYAxis {
            AxisMarks {
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel().font(.callout)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) {
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.callout)
            }
        }
        .frame(height: 210)
        .overlay(alignment: .topLeading) {
            if let day = selectedDay {
                Callout(title: day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                        value: "\(InsightsContent.decimal(day.words)) words")
            }
        }
    }
}

private struct ByHourChart: View {
    let hours: [HistoryStore.Analytics.Hour]
    @State private var selected: Int?

    var body: some View {
        Chart(hours) { hour in
            // Fixed width, not .ratio: on a numeric axis Charts has no step size
            // to take a ratio of, and silently draws nothing.
            BarMark(x: .value("Hour", hour.hour),
                    y: .value("Dictations", hour.count),
                    width: .fixed(9))
                .foregroundStyle(Theme.chartMark)
                .cornerRadius(4)
                .opacity(selected == nil || selected == hour.hour ? 1 : 0.35)
        }
        .chartXSelection(value: $selected)
        .chartXScale(domain: -0.5...23.5)
        .chartYAxis {
            AxisMarks {
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel().font(.callout)
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel { Text(Self.hourLabel(value.as(Int.self) ?? 0)).font(.callout) }
            }
        }
        .frame(height: 210)
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

/// GitHub-style activity grid: one column per week, one row per weekday.
/// Intensity is a magnitude, so it's a single-hue ramp — and the legend spells
/// the ends out, because a ramp read alone is guesswork.
private struct ActivityCalendar: View {
    let days: [HistoryStore.Analytics.CalendarDay]
    @State private var hovered: HistoryStore.Analytics.CalendarDay?

    private let cell: CGFloat = 15
    private let gap: CGFloat = 4

    private var weeks: [[HistoryStore.Analytics.CalendarDay]] {
        stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
    }

    /// The busiest day sets the top of the scale, so the ramp uses its full
    /// range whether the record is one dictation a day or thirty.
    private var peak: Int { max(1, days.map(\.dictations).max() ?? 1) }

    private func color(_ count: Int) -> Color {
        guard count > 0 else { return Theme.calendarEmpty }
        let steps = Theme.calendarSteps
        let ratio = Double(count) / Double(peak)
        return steps[min(steps.count - 1, Int(ratio * Double(steps.count - 1) + 0.5))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 7) {
                VStack(alignment: .trailing, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(Self.weekdayLabel(row))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(height: cell, alignment: .trailing)
                    }
                }
                .frame(width: 28)

                HStack(alignment: .top, spacing: gap) {
                    ForEach(weeks.indices, id: \.self) { index in
                        VStack(spacing: gap) {
                            ForEach(weeks[index]) { day in
                                DayCell(day: day, size: cell, fill: color(day.dictations),
                                        hovered: $hovered)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 5) {
                Text("Quieter").font(.caption).foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 3).fill(Theme.calendarEmpty)
                    .frame(width: 13, height: 13)
                ForEach(Theme.calendarSteps.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3).fill(Theme.calendarSteps[index])
                        .frame(width: 13, height: 13)
                }
                Text("Busier").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func weekdayLabel(_ row: Int) -> String {
        let calendar = Calendar.current
        let index = (calendar.firstWeekday - 1 + row) % 7
        return String(calendar.shortWeekdaySymbols[index].prefix(2))
    }
}

/// Ranked magnitudes with every row named and its value shown — a table that
/// happens to draw its numbers. No colour encodes identity, so the labels do.
private struct RankedBars: View {
    let buckets: [HistoryStore.Analytics.Bucket]
    let total: Int
    let label: (String) -> String
    /// Apps get their real icon; languages have none, so the column collapses.
    var icon: ((String) -> NSImage?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(buckets) { bucket in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        if let icon {
                            Group {
                                if let image = icon(bucket.name) {
                                    Image(nsImage: image).resizable()
                                } else {
                                    Image(systemName: "app.dashed")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 18, height: 18)
                        }
                        Text(label(bucket.name)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(bucket.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(percent(bucket.count))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                    .font(.body)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.chartTrack)
                            Capsule().fill(Theme.chartMark)
                                .frame(width: max(3, geometry.size.width * fraction(bucket.count)))
                        }
                    }
                    .frame(height: 7)
                }
            }
            if buckets.isEmpty {
                Text("No data yet.").font(.body).foregroundStyle(.secondary)
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
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.insetCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        .padding(6)
        .allowsHitTesting(false)
    }
}

/// The card surface itself — shared, so every card carries the same padding,
/// radius and border, and headline cards can stretch to a common height.
private struct CardShell<Content: View>: View {
    /// Only the headline row stretches — it's how the three cards stay level.
    /// Everywhere else a card sizes to its content, or leftover window height
    /// gets distributed into the cards as dead space.
    var stretch = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
            .padding(16)
            .background(Theme.insetCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
    }
}

private struct Card<Content: View>: View {
    let title: String
    let subtitle: String?
    var titleSize: CGFloat = 17
    var stretch = false
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String?, titleSize: CGFloat = 17,
         stretch: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.titleSize = titleSize
        self.stretch = stretch
        self.content = content()
    }

    var body: some View {
        CardShell(stretch: stretch) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: titleSize, weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                content
            }
        }
    }
}

/// One square. Split out because the popover, hover ring and fill together
/// were too much for the type-checker inline.
private struct DayCell: View {
    let day: HistoryStore.Analytics.CalendarDay
    let size: CGFloat
    let fill: Color
    @Binding var hovered: HistoryStore.Analytics.CalendarDay?

    private var isHovered: Bool { hovered?.id == day.id }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(ring)
            .onHover { inside in
                if inside { hovered = day } else if isHovered { hovered = nil }
            }
            .popover(isPresented: showDetail, arrowEdge: .top) { DayDetail(day: day) }
    }

    private var ring: some View {
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Theme.accent, lineWidth: isHovered ? 2 : 0)
    }

    /// Only days with activity have anything to say.
    private var showDetail: Binding<Bool> {
        Binding(get: { isHovered && day.dictations > 0 },
                set: { if !$0, isHovered { hovered = nil } })
    }
}

/// The hover card: what actually happened on that day.
private struct DayDetail: View {
    let day: HistoryStore.Analytics.CalendarDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.callout.weight(.semibold))
            Divider()
            row("Dictations", "\(day.dictations)")
            row("Words", InsightsContent.decimal(day.words))
            row("Apps used", "\(day.appsUsed)")
            if let top = day.topApp {
                row("Top app", InsightsContent.appName(top))
            }
        }
        .padding(14)
        .frame(width: 250)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}
