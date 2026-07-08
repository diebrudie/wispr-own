import SwiftUI

/// Reusable transcript list: search bar + day-grouped rows with a
/// reserved hover-action area (copy + ⋯ menu with Edit/Delete).
struct TranscriptList: View {
    @ObservedObject var app: AppState
    @State private var copiedId: Int64?
    @State private var editing: Transcript?

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
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { app.refreshRecent() }
        .sheet(item: $editing) { transcript in
            EditTranscriptSheet(transcript: transcript) { newText in
                app.updateTranscriptText(id: transcript.id, text: newText)
            }
        }
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
                            onEdit: { editing = transcript },
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
    let onEdit: () -> Void
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

            // Fixed-width action area — space is always reserved so the
            // text never reflows on hover (actions just fade in).
            HStack(spacing: 10) {
                Button(action: onCopy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(Theme.accent))
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                .help("Copy full transcript")

                Menu {
                    Button("Edit Transcript", systemImage: "pencil", action: onEdit)
                    Button("Delete Transcript", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.accent)
                        .frame(width: 18)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .frame(width: 60, alignment: .trailing)
            .opacity(hovering || copied ? 1 : 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Edit Transcript", action: onEdit)
            Button("Delete Transcript", role: .destructive, action: onDelete)
        }
    }

    private var time: String {
        guard let date = TranscriptList.parseDate(transcript.createdAt) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date).lowercased()
    }
}

/// Edit sheet: fix recognition slips, save, then copy the perfect version.
private struct EditTranscriptSheet: View {
    let transcript: Transcript
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(transcript: Transcript, onSave: @escaping (String) -> Void) {
        self.transcript = transcript
        self.onSave = onSave
        _text = State(initialValue: transcript.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Transcript")
                .font(.title3.weight(.semibold))
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 140)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(text)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 280)
        .tint(Theme.accent)
    }
}
