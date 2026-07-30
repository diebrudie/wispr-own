import AppKit

/// Spec 12 §E — learns personal vocabulary from the corrections the user makes
/// by hand. Fix "hupspot" to "HubSpot" in History and "HubSpot" becomes a
/// dictionary term, so Whisper spells it that way next time.
///
/// The signal is the edit itself, not a model: the app has the text before and
/// after, so a word diff names the corrected term outright. No API key needed.
///
/// Privacy line held (spec 12 §E): this reads only edits made inside WisprOwn's
/// own History view. Nothing observes typing in other apps.
enum TermLearner {
    /// One rewrite shouldn't be able to flood the dictionary.
    static let maxPerEdit = 3

    /// Words the user swapped in, filtered down to ones that look like personal
    /// vocabulary rather than ordinary edits.
    ///
    /// `isUnknown` is injected so the check is testable without AppKit's spell
    /// checker; it defaults to the system dictionary.
    static func learnedTerms(
        before: String,
        after: String,
        known: [String],
        isUnknown: (String) -> Bool = isUnknownToSystem
    ) -> [String] {
        let old = words(before)
        let new = words(after)

        // Stdlib diff. A substitution shows up as a removal and an insertion at
        // the same offset — which is exactly the shape of a correction. A pure
        // insertion is the user adding words, not fixing a mis-hearing, so
        // requiring both halves keeps ordinary edits out of the dictionary.
        var removedAt = Set<Int>()
        var insertedAt: [(offset: Int, word: String)] = []
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removedAt.insert(offset)
            case .insert(let offset, let word, _): insertedAt.append((offset, word))
            }
        }

        var learned: [String] = []
        var seen = Set(known.map { $0.lowercased() })
        for (offset, word) in insertedAt where removedAt.contains(offset) {
            guard learned.count < maxPerEdit else { break }
            guard isPersonalTerm(word, atStart: offset == 0, isUnknown: isUnknown) else { continue }
            guard seen.insert(word.lowercased()).inserted else { continue }
            learned.append(word)
        }
        return learned
    }

    /// Three ways a word earns a place in the dictionary:
    ///
    /// 1. An internal capital — HubSpot, WisprOwn, McKinsey.
    /// 2. A capital anywhere but the first word, i.e. a proper noun mid-sentence.
    /// 3. Absence from the system dictionary — lowercase jargon like `kubectl`.
    ///
    /// Rule 2 exists because the system checker turned out to accept *any*
    /// capitalised word as a proper noun, so "Bruda" reads as ordinary to it —
    /// exactly the kind of term worth learning. Rule 3 alone would miss every
    /// name. Together they still exclude ordinary fixes: correcting "teh" to
    /// "the" teaches Whisper nothing.
    static func isPersonalTerm(
        _ word: String, atStart: Bool, isUnknown: (String) -> Bool
    ) -> Bool {
        guard word.count >= 3, word.contains(where: \.isLetter) else { return false }
        if word.dropFirst().contains(where: { $0.isUppercase }) { return true }
        if !atStart, word.first?.isUppercase == true { return true }
        return isUnknown(word)
    }

    /// macOS already ships the word list — no bundled dictionary needed.
    static func isUnknownToSystem(_ word: String) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        return range.location != NSNotFound
    }

    /// Splits on punctuation and whitespace so "Jenn." and "Jenn" don't read as
    /// a substitution, while keeping hyphens and apostrophes inside a word.
    static func words(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "-" }
            .map(String.init)
    }
}
