import Foundation
import Testing
@testable import ScribeUI

struct RevealTextTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func openingDoesNotReplayAndAppendKeepsExistingWordHistory() {
        let initial = RevealState().updating(.init(text: "Hello", volatileTail: "Hello"), at: now, reduceMotion: false)
        #expect(initial.words.allSatisfy { $0.effect == .steady })
        #expect(initial.words[0].opacity(at: now) == 0.4)
        let next = initial.updating(.init(text: "Hello there everyone", volatileTail: "there everyone"), at: now, reduceMotion: false)
        #expect(next.words.map(\.text).joined() == "Hello there everyone")
        #expect(next.words[0].effect == .finalized)
        #expect(next.words[0].initialOpacity == 0.4)
        #expect(next.words[0].opacity(at: now.addingTimeInterval(0.15)) == 1)
        #expect(next.words[1].effect == .appended)
        #expect(next.words[2].start.timeIntervalSince(next.words[1].start) > 0.029)
        let again = next.updating(.init(text: "Hello there everyone today", volatileTail: "there everyone today"),
                                  at: now.addingTimeInterval(0.1), reduceMotion: false)
        #expect(again.words[1].start == next.words[1].start)
        #expect(again.words[2].start == next.words[2].start)
    }

    @Test func revisionCrossfadesAndReduceMotionHasNoStagger() {
        let initial = RevealState().updating(.init(text: "We can go", volatileTail: "can go"), at: now, reduceMotion: false)
        let revised = initial.updating(.init(text: "We could go", volatileTail: "could go"), at: now, reduceMotion: false)
        #expect(revised.words[1].effect == .revised)
        #expect(revised.words[1].duration == 0.15)
        #expect(revised.words[2].effect == .steady)
        #expect(revised.outgoing[0].words.map(\.index) == [1])
        #expect(revised.outgoing[0].words[0].initialOpacity == 0.4)
        #expect(revised.outgoing[0].generation == initial.generation)
        let appended = revised.updating(.init(text: "We could go today", volatileTail: "could go today"),
                                        at: now.addingTimeInterval(0.1), reduceMotion: false)
        #expect(appended.outgoing.first?.generation == revised.outgoing.first?.generation)
        #expect(appended.words.map(\.index) == [0, 1, 2, 3])
        let reduced = initial.updating(.init(text: "We can go together tomorrow", volatileTail: "tomorrow"), at: now, reduceMotion: true)
        #expect(reduced.words.suffix(2).allSatisfy { $0.start == now && $0.duration == 0.15 })
    }

    @Test func clippedKeyboardTailOnlyRevealsNewTrailingWords() {
        let initial = RevealState().updating(.init(text: "…one two three", volatileTail: "one two three"),
                                            at: now, reduceMotion: false)
        let next = initial.updating(.init(text: "…two three four", volatileTail: "one two three four"),
                                    at: now, reduceMotion: false)
        #expect(next.words.last?.effect == .appended)
        #expect(next.words[next.words.count - 2].effect == .steady)
        #expect(next.words.allSatisfy { $0.volatile })
    }

    @Test func largeBatchesFinishWithinThreeTenthsAndOldWordsSettle() {
        let first = RevealState().updating(.init(text: "Old", volatileTail: "Old"), at: now, reduceMotion: false)
        let batch = first.updating(.init(text: "Old " + String(repeating: "new ", count: 100), volatileTail: ""), at: now, reduceMotion: false)
        #expect(batch.end.timeIntervalSince(now) <= 0.301)
        let finalized = first.updating(.init(text: "Old", volatileTail: ""), at: now.addingTimeInterval(1), reduceMotion: false)
        #expect(finalized.words[0].duration == 0)
    }

    @Test func scrolledOffLinesLeaveLayoutOnlyAtWordStarts() {
        let text = (0..<12).map { "w\($0)" }.joined(separator: " ")
        var state = RevealState().updating(.init(text: text, volatileTail: "w11"), at: now, reduceMotion: false)
        state.generation = 7
        // Four words per 16 pt line, six lines; the window shows the last 20 pt.
        let lines = (0..<6).map { RevealLine(utf16Start: $0 * 12, bounds: CGRect(x: 0, y: CGFloat($0) * 16, width: 100, height: 16)) }
        let scrollback = RevealScrollback(visibleHeight: 20, layout: (generation: 7, lines: lines))
        let trimmed = state.updating(.init(text: text + " w12", volatileTail: "w11 w12"), at: now, reduceMotion: false, scrollback: scrollback)
        #expect(trimmed.dropped == 8)
        #expect(trimmed.words.count == 13)
        let stale = RevealScrollback(visibleHeight: 20, layout: (generation: 3, lines: lines))
        #expect(state.updating(.init(text: text + " w12", volatileTail: "w12"), at: now, reduceMotion: false, scrollback: stale).dropped == 0)
        let midToken = RevealScrollback(visibleHeight: 20, layout: (generation: 7, lines: lines.map {
            RevealLine(utf16Start: $0.utf16Start + 1, bounds: $0.bounds)
        }))
        #expect(state.updating(.init(text: text + " w12", volatileTail: "w12"), at: now, reduceMotion: false, scrollback: midToken).dropped == 0)
        let rewritten = trimmed.updating(.init(text: "fresh start", volatileTail: "start"), at: now, reduceMotion: false)
        #expect(rewritten.dropped == 0)
    }

    @Test func tokenizationPreservesEveryScriptAndWhitespace() {
        for text in ["你好世界。明天见", "明日は東京に行きます", "สวัสดีครับทุกคน", "مرحبا بكم جميعا", "Ciao,  Niccolò!\nA domani.", "…"] {
            let state = RevealState().updating(.init(text: text, volatileTail: text), at: now, reduceMotion: false)
            #expect(state.words.map(\.text).joined() == text)
            #expect(state.words.allSatisfy { $0.volatile })
        }
    }
}
