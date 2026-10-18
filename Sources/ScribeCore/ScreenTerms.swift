import Foundation
import NaturalLanguage

/// Bounded, local vocabulary hints. Casing is evidence only in scripts that have case;
/// structured identifiers and the system's name tagger work independently of it.
public enum ScreenTerms {
    public static func nearCursor(in text: String, offset: Int) -> String {
        let cursor = min(max(0, offset), text.count)
        return String(text.dropFirst(max(0, cursor - 1_500)).prefix(min(text.count, cursor + 1_500) - max(0, cursor - 1_500)))
    }

    public static func extract(from text: String, nearCursor: String? = nil, cursorOffset: Int? = nil) -> [String] {
        struct Candidate {
            var text: String
            var frequency = 0
            var near = false
            var distance = Int.max
            var strength = 0
            var order: Int
        }
        var candidates: [String: Candidate] = [:]
        var order = 0
        func add(_ value: String, near: Bool, strength: Int, distance: Int = .max) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count > 1, value.count <= 150 else { return }
            let key = value.precomposedStringWithCanonicalMapping.lowercased()
            var candidate = candidates[key] ?? Candidate(text: value, order: order)
            candidate.frequency += 1
            candidate.near = candidate.near || near
            candidate.distance = min(candidate.distance, distance)
            candidate.strength = max(candidate.strength, strength)
            candidates[key] = candidate
            order += 1
        }
        // These words at sentence starts are weak evidence even when repeated. Away
        // from sentence starts, ordinary capitals (including German nouns) remain useful.
        let commonStarts: Set<String> = [
            "the", "this", "that", "please", "hello", "thanks", "thank", "we", "you", "it", "i", "a", "an",
            "il", "la", "lo", "le", "gli", "un", "una", "grazie", "ciao", "questo", "questa",
            "der", "die", "das", "ein", "eine", "bitte", "danke", "ich", "wir", "sie", "es",
        ]
        func scan(_ source: String, near: Bool) {
            let source = String(source.prefix(40_000))
            let ns = source as NSString
            let pattern = #"[\p{L}\p{M}\p{N}._%+\-]+@[\p{L}\p{M}\p{N}.\-]+\.[\p{L}\p{M}]{2,}|[@#][\p{L}\p{M}\p{N}_]+|[\p{L}\p{M}][\p{L}\p{M}\p{N}_'’\-]*"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let cursor = source.index(source.startIndex, offsetBy: min(max(0, cursorOffset ?? source.count / 2), source.count))
            let cursorUTF16 = NSRange(source.startIndex..<cursor, in: source).length
            let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
            var previousEnd = 0
            var previousCapital: (text: String, end: Int)?
            for match in matches {
                if Task.isCancelled { return }
                let distance = near ? abs(match.range.location - cursorUTF16) : Int.max
                let word = ns.substring(with: match.range)
                let scalars = word.unicodeScalars
                let upper = scalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
                let lower = scalars.filter { CharacterSet.lowercaseLetters.contains($0) }.count
                let structured = word.contains("@") || word.hasPrefix("#") || scalars.contains { CharacterSet.decimalDigits.contains($0) }
                let mixedCase = upper > 0 && lower > 0 && (word.first?.isLowercase == true || upper > 1)
                let capital = word.first?.isUppercase == true
                let gap = ns.substring(with: NSRange(location: previousEnd, length: match.range.location - previousEnd))
                let initial = previousEnd == 0 || gap.contains("\n") || gap.contains { ".!?。！？:".contains($0) }
                defer { previousEnd = NSMaxRange(match.range) }
                if structured || mixedCase || (upper > 1 && lower == 0) {
                    add(word, near: near, strength: 3, distance: distance)
                } else if capital && (!initial || !commonStarts.contains(word.lowercased())) {
                    add(word, near: near, strength: initial ? 1 : 2, distance: distance)
                }
                if capital, !commonStarts.contains(word.lowercased()) {
                    if let previous = previousCapital {
                        let gap = ns.substring(with: NSRange(location: previous.end, length: match.range.location - previous.end))
                        if !gap.isEmpty, gap.allSatisfy({ $0 == " " || $0 == "\t" }) {
                            let phrase = previous.text + " " + word
                            add(phrase, near: near, strength: 3, distance: distance)
                            previousCapital = (String(phrase.split(separator: " ").suffix(3).joined(separator: " ")), NSMaxRange(match.range))
                            continue
                        }
                    }
                    previousCapital = (word, NSMaxRange(match.range))
                } else {
                    previousCapital = nil
                }
            }
            // Keep linguistic analysis cheap. Prioritize the cursor separately, then a
            // bounded window tail where chat's newest messages normally live.
            let namedText = String(source.suffix(8_000))
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = namedText
            guard !Task.isCancelled else { return }
            tagger.enumerateTags(in: namedText.startIndex..<namedText.endIndex, unit: .word, scheme: .nameType,
                                 options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
                if tag == .personalName || tag == .organizationName || tag == .placeName {
                    let name = String(namedText[range])
                    let location = NSRange(range, in: namedText).location + source.utf16.count - namedText.utf16.count
                    let distance = near ? abs(location - cursorUTF16) : Int.max
                    if !commonStarts.contains(name.lowercased()) { add(name, near: near, strength: 3, distance: distance) }
                }
                return !Task.isCancelled
            }
        }
        if let nearCursor { scan(nearCursor, near: true) }
        scan(text, near: false)
        // A lone sentence-initial capital needs another signal: recurrence, an
        // interior occurrence, an identifier shape, or linguistic name recognition.
        return candidates.values.filter { $0.strength > 1 || $0.frequency > 1 }.sorted {
            if $0.near != $1.near { return $0.near }
            if $0.near, $0.distance / 200 != $1.distance / 200 { return $0.distance < $1.distance }
            if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
            if $0.strength != $1.strength { return $0.strength > $1.strength }
            return $0.order < $1.order
        }.prefix(100).map(\.text)
    }
}
