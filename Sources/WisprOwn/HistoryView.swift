import SwiftUI

/// Spec 06 — last 20 transcripts, newest first, per-row copy button.
/// Modeled on the Wispr Flow history screenshot. Search comes in v2.
struct HistoryView: View {
    @ObservedObject var app: AppState
    @State private var copiedId: Int64?

    var body: some View {
        Group {
            if app.recentTranscripts.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "mic",
                    description: Text("Hold Left Option and speak — transcripts land here.")
                )
            } else {
                List(app.recentTranscripts) { transcript in
                    HistoryRow(
                        transcript: transcript,
                        copied: copiedId == transcript.id,
                        onCopy: { copy(transcript) }
                    )
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("History")
        .onAppear { app.refreshRecent() }
    }

    private func copy(_ transcript: Transcript) {
        app.copyToClipboard(transcript.text)
        copiedId = transcript.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedId == transcript.id { copiedId = nil }
        }
    }
}

private struct HistoryRow: View {
    let transcript: Transcript
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(displayTime)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(transcript.text)
                .font(.body)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Button(action: onCopy) {
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "doc.on.doc")
                }
            }
            .buttonStyle(.borderless)
            .help("Copy full transcript")
        }
        .padding(.vertical, 6)
    }

    /// "2:35 pm" for today, otherwise "Jul 7, 2:35 pm".
    private var displayTime: String {
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        guard let date = iso.date(from: transcript.createdAt) else { return "" }

        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a" : "MMM d, h:mm a"
        return f.string(from: date).lowercased()
    }
}
