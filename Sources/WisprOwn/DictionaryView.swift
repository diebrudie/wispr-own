import SwiftUI

/// Dictionary screen (Spec 10): personal terms that bias Whisper so names
/// and jargon transcribe correctly. Modeled on the Wispr Flow layout.
struct DictionaryView: View {
    @ObservedObject var app: AppState
    @State private var query = ""
    @State private var adding = false
    @State private var newPhrase = ""
    @State private var editingId: Int64?
    @State private var editText = ""
    @FocusState private var addFieldFocused: Bool

    private var filtered: [HistoryStore.DictionaryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return app.dictionary }
        return app.dictionary.filter { $0.phrase.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            explainer
            searchField
            if filtered.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .padding(24)
        .pageWidth()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.windowBackground)
        .onAppear { app.refreshDictionary() }
    }

    private var header: some View {
        HStack {
            Text("Dictionary")
                .font(.system(size: 30, weight: .semibold))
            Spacer()
            Button {
                adding = true
                addFieldFocused = true
            } label: {
                Label("Add new", systemImage: "plus")
            }
            .buttonStyle(.primary)
        }
    }

    /// A card rather than a grey paragraph: as plain secondary text under the
    /// title, this explanation reads as decoration and gets skipped, which is
    /// how the page ends up feeling like a list with no purpose.
    @ViewBuilder
    private var explainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WisprOwn spells the way you do.")
                .font(.system(size: 20, weight: .semibold))
            Text("Every word here is handed to the transcriber as context, so your names, company jargon and product terms come out right — no more \u{201C}Gotar\u{201D} for \u{201C}Gothaer\u{201D}.")
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            Text("It also learns on its own: correct a word while editing a transcript and it lands here automatically.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !app.dictionary.isEmpty {
                HStack(spacing: 7) {
                    ForEach(app.dictionary.prefix(5)) { entry in
                        Text(entry.phrase)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Theme.cardBackground.opacity(0.85), in: Capsule())
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.tintedFill, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))

        if adding {
            HStack {
                TextField("New word or phrase…", text: $newPhrase)
                    .textFieldStyle(.roundedBorder)
                    .focused($addFieldFocused)
                    .onSubmit(commitAdd)
                Button("Add", action: commitAdd)
                    .buttonStyle(.primary)
                    .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") {
                    adding = false
                    newPhrase = ""
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search dictionary…", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            query.isEmpty ? "No words yet" : "No matches",
            systemImage: "character.book.closed",
            description: Text(query.isEmpty
                ? "Add names and terms Whisper gets wrong — they'll transcribe correctly from then on."
                : "No entry contains “\(query)”.")
        )
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        List(filtered) { entry in
            DictionaryRow(
                entry: entry,
                isEditing: editingId == entry.id,
                editText: $editText,
                onEdit: {
                    editingId = entry.id
                    editText = entry.phrase
                },
                onCommit: {
                    app.updateDictionaryEntry(id: entry.id, phrase: editText)
                    editingId = nil
                },
                onCancel: { editingId = nil },
                onDelete: { app.deleteDictionaryEntry(id: entry.id) }
            )
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func commitAdd() {
        if app.addDictionaryEntry(newPhrase) {
            newPhrase = ""
            addFieldFocused = true // stay in flow for adding several terms
        }
    }
}

private struct DictionaryRow: View {
    let entry: HistoryStore.DictionaryEntry
    let isEditing: Bool
    @Binding var editText: String
    let onEdit: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onCommit)
                Button("Save", action: onCommit).buttonStyle(.primary)
                Button("Cancel", action: onCancel)
            } else {
                Text(entry.phrase)
                Spacer()
                if hovering {
                    Button(action: onEdit) { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help("Edit")
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Delete")
                }
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
