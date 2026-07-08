import SwiftUI

/// Reusable transcript list: search bar + day-grouped rows with copy/delete.
/// Embedded in HomeView; kept standalone so future screens can reuse it.
struct TranscriptList: View {
    @ObservedObject var app: AppState
    @State private var copiedId: Int64?

    private var groups: [(day: String, items: [Transcript])] {
        var order: [String] = []
        var byDay: [String: [Transcript]] = [:]
        for t in app.recentTranscripts {
            let day = Self.dayLabel(for: t.createdAt)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(t)
        }
        return order.map { ($0, byDay[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if app.recentTranscripts.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { app.refreshRecent() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search all dictations…", text: $app.searchQuery)
                .textFieldStyle(.plain)
            if !app.searchQuery.isEmpty {
                Button {
                    app.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            app.searchQuery.isEmpty ? "No dictations yet" : "No matches",
            systemImage: app.searchQuery.isEmpty ? "mic" : "magnifyingglass",
            description: Text(app.searchQuery.isEmpty
                ? "Hold \(HotkeyOption.current.displayName) and speak — transcripts land here."
                : "No dictation contains “\(app.searchQuery)”.")
        )
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.day) { group in
                Section {
                    ForEach(group.items) { transcript in
                        HistoryRow(
                            transcript: transcript,
                            copied: copiedId == transcript.id,
                            onCopy: { copy(transcript) },
                            onDelete: { app.deleteTranscript(transcript) }
                        )
                    }
                } header: {
                    Text(group.day)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func copy(_ transcript: Transcript) {
        app.copyToClipboard(transcript.text)
        copiedId = transcript.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedId == transcript.id { copiedId = nil }
        }
    }

    static func parseDate(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return f.date(from: iso)
    }

    static func dayLabel(for iso: String) -> String {
        guard let date = parseDate(iso) else { return "Earlier" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }
}

struct HistoryRow: View {
    let transcript: Transcript
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(transcript.text)
                    .font(.body)
                    .lineLimit(4)
                    .textSelection(.enabled)
                if let language = transcript.language {
                    Text(language.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.tintedFill, in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button(action: onCopy) {
                    if copied {
                        Label("Copied", systemImage: "checkmark").foregroundStyle(.green)
                    } else {
                        Image(systemName: "doc.on.doc")
                    }
                }
                .buttonStyle(.borderless)
                .help("Copy full transcript")

                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this dictation")
                }
            }
        }
        .padding(.vertical, 6)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var time: String {
        guard let date = TranscriptList.parseDate(transcript.createdAt) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date).lowercased()
    }
}
