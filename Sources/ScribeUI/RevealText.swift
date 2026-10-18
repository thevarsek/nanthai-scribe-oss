import NaturalLanguage
import os
import SwiftUI

/// A live transcript whose word effects never change its text layout. Pass the complete
/// text and, when available, its still-revising suffix. Existing text opens without animation.
/// Reduce Motion follows the system unless the caller explicitly supplies a preference.
///
/// The text itself is laid out only when the transcript changes: its renderer depends on
/// nothing that varies per frame. Words still animating are hidden there and drawn each
/// frame by a `Canvas` from the glyph runs the renderer captured, so a frame costs a few
/// run draws however long the transcript is.
///
/// A caller that shows only the bottom `visibleHeight` points, like the Mac HUD, can say so:
/// whole lines that scrolled well above that window are then left out of layout. Dropping
/// at a line start leaves every line below wrapped exactly as before.
public struct RevealText: View {
    private let input: RevealInput
    private let motionOverride: Bool?
    private let visibleHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var state = RevealState()
    @State private var animating = false
    @State private var captures = RevealCaptures()

    public init(_ text: String, volatileTail: String = "", reduceMotion: Bool? = nil, visibleHeight: CGFloat? = nil) {
        input = RevealInput(text: text, volatileTail: volatileTail)
        motionOverride = reduceMotion
        self.visibleHeight = visibleHeight
    }

    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }

    public var body: some View {
        // Use the new input immediately, including the frame before onChange commits
        // its animation history. Never queue or delay the actual transcript.
        let captures = captures
        let scrollback = visibleHeight.map { RevealScrollback(visibleHeight: $0, layout: captures.lines()) }
        let current = state.input == input ? state
            : state.updating(input, at: .now, reduceMotion: reduceMotion, scrollback: scrollback)
        let active = current.words.filter { $0.isAnimating(at: current.clock) }
        let outgoing = current.outgoing
        let reduceMotion = reduceMotion
        let (text, spans) = Self.rendered(current)
        text
            .textRenderer(SettledWordRenderer(clock: current.clock, generation: current.generation, spans: spans, captures: captures))
            .overlay(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animating)) { context in
                    Canvas { graphics, _ in
                        let runs = captures.snapshot()
                        for word in active {
                            guard let slices = runs.slices(for: word, preferring: current.generation) else { continue }
                            var copy = graphics
                            copy.opacity *= word.opacity(at: context.date)
                            if word.effect == .appended, !reduceMotion {
                                // Opacity and rise avoid offscreen blur passes on Mac and Simulator.
                                copy.translateBy(x: 0, y: 3 * (1 - word.progress(at: context.date)))
                            }
                            guard copy.opacity > 0 else { continue }
                            for slice in slices { copy.draw(slice) }
                        }
                        for layer in outgoing where layer.end > context.date {
                            for word in layer.words {
                                guard let slices = runs.slices(for: word, in: layer.generation) else { continue }
                                var copy = graphics
                                copy.opacity *= word.initialOpacity * (1 - word.progress(at: context.date))
                                guard copy.opacity > 0 else { continue }
                                for slice in slices { copy.draw(slice) }
                            }
                        }
                    }
                }
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(input.text)
            .onChange(of: input, initial: true) { _, value in
                let now = Date.now
                let next = current.input == value ? current
                    : state.updating(value, at: now, reduceMotion: reduceMotion, scrollback: scrollback)
                state = next
                animating = next.end > now
            }
            .task(id: state.end) {
                guard animating else { return }
                try? await Task.sleep(for: .seconds(max(0, state.end.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                animating = false
                state.settle(at: .now)
            }
            .transaction { $0.animation = nil }
    }

    /// One plain `Text` of the words in layout, plus the spans the renderer must treat
    /// specially: volatile words draw dimmed and animating ones belong to the overlay.
    /// A verbatim string skips SwiftUI's localized-interpolation resolution, which was the
    /// single largest cost per update when each word was its own attributed `Text`. The
    /// result depends only on the state, never on the wall clock, so it changes exactly
    /// when the layout must.
    static func rendered(_ state: RevealState) -> (Text, [RevealSpan]) {
        var text = ""
        var spans: [RevealSpan] = []
        for word in state.words[state.dropped...] {
            let start = text.utf16.count
            text += word.text
            if word.volatile || word.isAnimating(at: state.clock) {
                spans.append(RevealSpan(utf16: start..<text.utf16.count, word: word))
            }
        }
        return (Text(verbatim: text), spans)
    }
}

/// A word's place in the rendered text, in UTF-16 offsets as `Text.Layout` counts them.
struct RevealSpan: Equatable {
    var utf16: Range<Int>
    var word: RevealWord
}

struct RevealInput: Equatable {
    var text: String
    var volatileTail: String
}

struct RevealWord: Equatable {
    enum Effect: Hashable { case steady, appended, revised, finalized, removed }
    var text: String
    var volatile: Bool
    /// Position in the transcript when its glyphs were laid out; the key for captured runs.
    var index = 0
    var effect: Effect = .steady
    var arrived = Date.distantPast
    var start = Date.distantPast
    var duration = 0.0
    var initialOpacity = 1.0

    var opacity: Double { volatile ? 0.4 : 1 }
    var end: Date { start.addingTimeInterval(duration) }

    /// Animate only words that arrived in the last 0.3 s; older ones render plain.
    func isAnimating(at time: Date) -> Bool {
        end > time && time.timeIntervalSince(arrived) < 0.3
    }

    func progress(at time: Date) -> Double {
        guard duration > 0 else { return 1 }
        let linear = min(1, max(0, time.timeIntervalSince(start) / duration))
        // UnitCurve is the same ease-out curve used by SwiftUI animations.
        return UnitCurve.easeOut.value(at: linear)
    }

    func opacity(at time: Date) -> Double {
        initialOpacity + (opacity - initialOpacity) * progress(at: time)
    }

    /// Crossfades from the current opacity to the new steady one, finishing within 0.3 s
    /// of arrival.
    mutating func finalize(at now: Date, volatile: Bool) {
        let from = opacity(at: now)
        self.volatile = volatile
        effect = .finalized
        start = now
        duration = min(0.15, max(0, 0.3 - now.timeIntervalSince(arrived)))
        initialOpacity = from
    }
}

/// Animation history is separate from recognition state: revisions and finalization
/// retain word identity, and an append cannot replay a previous word's reveal.
struct RevealState {
    var input: RevealInput?
    var words: [RevealWord] = []
    var outgoing: [RevealLayer] = []
    var end = Date.distantPast
    /// Time of the last transition; which words count as animating is decided here, not
    /// per frame, so the rendered text is a pure function of the state.
    var clock = Date.distantPast
    /// Bumps whenever the rendered text can change, tagging the glyph runs captured from it.
    var generation = 0
    /// Leading words left out of layout because their lines scrolled out of view.
    var dropped = 0

    func updating(_ input: RevealInput, at now: Date, reduceMotion: Bool, scrollback: RevealScrollback? = nil) -> Self {
        guard self.input != input else { return self }
        var next = Self(input: input, outgoing: outgoing.filter { $0.end > now }, end: end,
                        clock: now, generation: generation + 1)
        let boundary = Self.volatileBoundary(of: input)
        // Words before the first changed byte keep their layout and history; only the
        // tail after them is re-tokenised and diffed, so a long transcript costs the same
        // per partial result as a short one.
        let (kept, keptEnd) = self.input.map { Self.unchangedPrefix(of: words, from: $0.text, to: input.text) } ?? (0, 0)
        next.words = Array(words[..<kept])
        // Only an unchanged prefix can stay out of layout; a rewrite before it starts over.
        next.dropped = dropped <= kept ? dropped : 0
        if let scrollback, scrollback.layout.generation == generation, next.dropped == dropped,
           let trimmed = scrollback.firstKeptWord(in: words, dropped: dropped), trimmed <= kept {
            next.dropped = trimmed
        }
        var wordEnd = keptEnd
        for index in stride(from: kept - 1, through: 0, by: -1) {
            let volatile = wordEnd > boundary
            if next.words[index].volatile != volatile {
                next.words[index].finalize(at: now, volatile: volatile)
                next.end = max(next.end, next.words[index].end)
            } else if !volatile {
                break // Volatile words are a suffix, so everything earlier is settled.
            }
            wordEnd -= next.words[index].text.utf8.count
        }
        let offset = input.text.utf8.index(input.text.utf8.startIndex, offsetBy: keptEnd)
        var tailEnd = keptEnd
        let oldTail = Array(words[kept...])
        var newTail = Self.tokens(in: input.text[offset...]).map { token -> RevealWord in
            tailEnd += token.utf8.count
            return RevealWord(text: String(token), volatile: tailEnd > boundary, arrived: now)
        }
        // Match unchanged words even when a keyboard clips words off the leading edge.
        let oldText = oldTail.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let newText = newTail.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let difference = newText.difference(from: oldText)
        let removed = Set(difference.removals.compactMap { change -> Int? in
            if case .remove(let offset, _, _) = change { return offset }
            return nil
        })
        let inserted = Set(difference.insertions.compactMap { change -> Int? in
            if case .insert(let offset, _, _) = change { return offset }
            return nil
        })
        let oldKept = oldTail.indices.filter { !removed.contains($0) }
        let newKept = newTail.indices.filter { !inserted.contains($0) }
        let matches = Dictionary(uniqueKeysWithValues: zip(newKept, oldKept))
        let lastKeptNew = newKept.last ?? -1
        let replacedTailCount = oldTail.count - ((oldKept.last ?? -1) + 1)
        var appendIndex = 0
        for index in newTail.indices {
            if let oldIndex = matches[index] {
                let new = newTail[index]
                newTail[index] = oldTail[oldIndex]
                newTail[index].text = new.text
                if new.volatile != newTail[index].volatile { newTail[index].finalize(at: now, volatile: new.volatile) }
            } else if self.input != nil {
                let appended = index > lastKeptNew + replacedTailCount
                newTail[index].effect = appended ? .appended : .revised
                newTail[index].start = now.addingTimeInterval(appended && !reduceMotion ? min(0.08, Double(appendIndex) * 0.03) : 0)
                newTail[index].duration = appended && !reduceMotion ? 0.22 : 0.15
                newTail[index].initialOpacity = 0
                if appended { appendIndex += 1 }
            }
            newTail[index].index = kept + index
            next.end = max(next.end, newTail[index].end)
        }
        next.words.append(contentsOf: newTail)
        if !removed.isEmpty {
            // Removed words fade where they were, drawn from the runs captured for the
            // previous generation of the text.
            let fading = removed.sorted().map { index -> RevealWord in
                var word = oldTail[index]
                word.effect = .removed
                word.initialOpacity = word.opacity(at: now)
                word.start = now
                word.duration = 0.15
                return word
            }
            next.outgoing.append(RevealLayer(generation: generation, words: fading, end: now.addingTimeInterval(0.15)))
            next.end = max(next.end, now.addingTimeInterval(0.15))
        }
        return next
    }

    /// Every effect has finished: animating words become plain runs and fades are dropped.
    mutating func settle(at now: Date) {
        clock = now
        generation += 1
        outgoing = []
    }

    /// Words wholly inside the common prefix of the old and new text, and their byte length.
    /// Stops one word early so a last word that merely gained trailing whitespace is
    /// re-tokenised whole.
    private static func unchangedPrefix(of words: [RevealWord], from old: String, to new: String) -> (count: Int, bytes: Int) {
        var old = old, new = new
        let common = old.withUTF8 { oldBytes in
            new.withUTF8 { newBytes in
                let limit = min(oldBytes.count, newBytes.count)
                var index = 0
                while index < limit, oldBytes[index] == newBytes[index] { index += 1 }
                return index
            }
        }
        var count = words.count
        var bytes = old.utf8.count
        while count > 0, bytes > common {
            count -= 1
            bytes -= words[count].text.utf8.count
        }
        if count > 0 {
            count -= 1
            bytes -= words[count].text.utf8.count
        }
        return (count, bytes)
    }

    /// Each token carries the whitespace and punctuation that follow it, so tokens
    /// concatenate back to the exact text.
    private static func tokens(in text: Substring) -> [Substring] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        let string = String(text)
        tokenizer.string = string
        let ranges = tokenizer.tokens(for: string.startIndex..<string.endIndex)
        let starts = [string.startIndex] + ranges.dropFirst().map(\.lowerBound)
        let ends = Array(starts.dropFirst()) + [string.endIndex]
        return zip(starts, ends).map { string[$0..<$1] }
    }

    /// Byte offset where the still-revising tail begins.
    private static func volatileBoundary(of input: RevealInput) -> Int {
        let text = input.text
        if text.hasSuffix(input.volatileTail) { return text.utf8.count - input.volatileTail.utf8.count }
        let visible = text.hasPrefix("…") ? text.dropFirst() : text[...]
        if !visible.isEmpty, input.volatileTail.hasSuffix(visible) { return 0 }
        return text.utf8.count
    }
}

/// One laid-out line: where it starts in the rendered text (UTF-16 offsets, as
/// `Text.Layout` counts) and where it sits.
struct RevealLine {
    var utf16Start: Int
    var bounds: CGRect
}

/// The caller's visible window and the lines of the current layout, for trimming.
struct RevealScrollback {
    var visibleHeight: CGFloat
    var layout: (generation: Int, lines: [RevealLine])

    /// The first word of the line two above the visible window, when a line starts exactly
    /// at a word; the lines kept above the window preserve the fade and clip the HUD shows.
    func firstKeptWord(in words: [RevealWord], dropped: Int) -> Int? {
        let lines = layout.lines
        guard let bottom = lines.last?.bounds.maxY,
              let visible = lines.firstIndex(where: { $0.bounds.maxY > bottom - visibleHeight }),
              visible >= 2 else { return nil }
        let target = lines[visible - 2].utf16Start
        var offset = 0
        for index in dropped..<words.count {
            if offset == target { return index }
            if offset > target { return nil }
            offset += words[index].text.utf16.count
        }
        return nil
    }
}

/// Words removed by one revision, fading out together.
struct RevealLayer {
    /// The text generation whose captured runs still hold these words' glyphs.
    let generation: Int
    var words: [RevealWord]
    let end: Date
}

/// Glyph slices of special words, keyed by text generation and word index. Written by the
/// text renderer during display, read by the overlay canvas each frame; the lock keeps that
/// pairing honest without tying either to an actor.
final class RevealCaptures: @unchecked Sendable {
    typealias Slices = [Int: (word: RevealWord, slices: [Text.Layout.RunSlice])]

    /// Slices are immutable layout values that are only ever read once captured.
    struct Snapshot: @unchecked Sendable {
        var generations: [Int: Slices]

        /// The glyphs laid out for `word` in `generation`, or the newest older generation
        /// where it still read the same, so a word mid-reveal survives the frame between a
        /// text change and its first display.
        func slices(for word: RevealWord, preferring generation: Int) -> [Text.Layout.RunSlice]? {
            for candidate in generations.keys.sorted(by: >) where candidate <= generation {
                if let entry = generations[candidate]?[word.index], entry.word.text == word.text { return entry.slices }
            }
            return nil
        }

        func slices(for word: RevealWord, in generation: Int) -> [Text.Layout.RunSlice]? {
            guard let entry = generations[generation]?[word.index], entry.word.text == word.text else { return nil }
            return entry.slices
        }
    }

    private let storage = OSAllocatedUnfairLock(initialState: Snapshot(generations: [:]))
    private let layout = OSAllocatedUnfairLock(initialState: (generation: -1, lines: [RevealLine]()))

    func record(_ runs: Slices, lines: [RevealLine], generation: Int) {
        layout.withLock { $0 = (generation, lines) }
        storage.withLockUnchecked { snapshot in
            snapshot.generations[generation] = runs
            // Fades reference at most a few generations back; drop the rest.
            for stale in snapshot.generations.keys where stale < generation - 3 {
                snapshot.generations[stale] = nil
            }
        }
    }

    func snapshot() -> Snapshot { storage.withLock { $0 } }

    func lines() -> (generation: Int, lines: [RevealLine]) { layout.withLock { $0 } }
}

/// Draws settled words and captures the glyphs of special ones. Its value changes only
/// with the state, so SwiftUI never re-lays out the transcript for a frame.
private struct SettledWordRenderer: TextRenderer {
    var clock: Date
    var generation: Int
    var spans: [RevealSpan]
    var captures: RevealCaptures

    var displayPadding: EdgeInsets { EdgeInsets(top: 7, leading: 4, bottom: 7, trailing: 4) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var captured: RevealCaptures.Slices = [:]
        var lines: [RevealLine] = []
        let origin = layout.first?.first?.characterIndices.first
        for line in layout {
            if let origin, let first = line.first?.characterIndices.first {
                lines.append(RevealLine(utf16Start: origin.distance(to: first), bounds: line.typographicBounds.rect))
            }
            for run in line {
                guard let origin, !spans.isEmpty else { context.draw(run); continue }
                // Glyphs are grouped by the span they belong to, so a word stays one slice
                // whichever direction its script runs in.
                var start = run.startIndex
                var current = span(at: run[start], from: origin)
                for index in run.indices.dropFirst() where span(at: run[index], from: origin) != current {
                    draw(run[start..<index], span: current, into: &context, captured: &captured)
                    start = index
                    current = span(at: run[index], from: origin)
                }
                draw(run[start...], span: current, into: &context, captured: &captured)
            }
        }
        captures.record(captured, lines: lines, generation: generation)
    }

    private func span(at glyph: Text.Layout.RunSlice, from origin: Text.Layout.CharacterIndex) -> Int? {
        guard let first = glyph.characterIndices.first else { return nil }
        let offset = origin.distance(to: first)
        return spans.firstIndex { $0.utf16.contains(offset) }
    }

    private func draw(_ slice: Text.Layout.RunSlice, span: Int?, into context: inout GraphicsContext,
                      captured: inout RevealCaptures.Slices) {
        guard let span else { context.draw(slice); return }
        let word = spans[span].word
        captured[word.index, default: (word, [])].slices.append(slice)
        // Animating words belong to the overlay until the next generation.
        guard !word.isAnimating(at: clock) else { return }
        var copy = context
        copy.opacity *= word.opacity
        copy.draw(slice)
    }
}
