import SwiftUI

/// Home screen: welcome headline, stats card (right column), and
/// the recent-dictations list with search — per the Wispr Flow mock.
struct HomeView: View {
    @ObservedObject var app: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome back, \(app.greetingName)")
                    .font(.largeTitle.weight(.semibold))
                TranscriptList(app: app)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatsCard(stats: app.stats)
                .frame(width: 200)
                .padding(.top, 52) // aligns with the list, below the headline
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.windowBackground)
        .onAppear { app.refreshRecent() }
    }
}

private struct StatsCard: View {
    let stats: HistoryStore.Stats

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statRow(value: formattedWords, unit: "total words")
            statRow(value: "\(stats.wordsPerMinute)", unit: "wpm")
            statRow(value: "\(stats.dayStreak)", unit: stats.dayStreak == 1 ? "day streak" : "days streak")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func statRow(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.title.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.accent)
            Text(unit)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// 54,092 → "54.1K" above 10k, exact below.
    private var formattedWords: String {
        let words = stats.totalWords
        if words >= 10_000 {
            return String(format: "%.1fK", Double(words) / 1000)
        }
        return NumberFormatter.localizedString(from: NSNumber(value: words), number: .decimal)
    }
}
