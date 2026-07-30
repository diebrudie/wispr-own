import SwiftUI

/// Flow-style transcript list: day headers and the search loop live
/// OUTSIDE the rounded cards; each day's rows sit inside their own card;
/// rows highlight on hover.
struct TranscriptList: View {
    @ObservedObject var app: AppState
    @State private var copiedId: Int64?
    @State private var editing: Transcript?
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if groups.isEmpty {
                    header(label: "Today", showsSearch: true)
                    emptyState
                } else {
                    ForEach(Array(groups.enumerated()), id: \.element.day) { index, group in
                        VStack(alignment: .leading, spacing: 10) {
                            header(label: group.day, showsSearch: index == 0)
                            card(group.items)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .onAppear { app.refreshRecent() }
        .sheet(item: $editing) { transcript in
            EditTranscriptSheet(transcript: transcript) { newText in
                app.updateTranscriptText(id: transcript.id, text: newText)
            }
        }
    }

    /// "TODAY"-style label left, search loop right — both outside the card.
    private func header(label: String, showsSearch: Bool) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)
            Spacer()
            if showsSearch {
                searchControl
            }
        }
        // Fixed height: the search field is taller than the icon it replaces,
        // so without this the whole list jumps down when the loop is clicked.
        .frame(height: 30)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var searchControl: some View {
        if searchOpen || !app.searchQuery.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all dictations…", text: $app.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .frame(width: 200)
                Button {
                    app.searchQuery = ""
                    searchOpen = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border))
        } else {
            Button {
                searchOpen = true
                searchFocused = true
            } label: {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Search all dictations")
        }
    }

    private func card(_ items: [Transcript]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, transcript in
                HistoryRow(
                    transcript: transcript,
                    copied: copiedId == transcript.id,
                    onCopy: { copy(transcript) },
                    onEdit: { editing = transcript },
                    onDelete: { app.deleteTranscript(transcript) }
                )
                if index < items.count - 1 {
                    Divider().padding(.horizontal, 16)
                }
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            app.searchQuery.isEmpty ? "No dictations yet" : "No matches",
            systemImage: app.searchQuery.isEmpty ? "mic" : "magnifyingglass",
            description: Text(app.searchQuery.isEmpty
                ? "Hold \(HotkeyOption.current.displayName) and speak — transcripts land here."
                : "No dictation contains “\(app.searchQuery)”.")
        )
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(hovering ? Theme.rowHover : Color.clear)
        .animation(.easeOut(duration: 0.12), value: hovering)
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
