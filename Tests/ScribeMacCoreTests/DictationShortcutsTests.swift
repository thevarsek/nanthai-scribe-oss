import Testing
@testable import ScribeMacCore

@Suite struct DictationShortcutsTests {
    private func handsFree() -> DictationShortcuts {
        var state = DictationShortcuts()
        _ = state.handle(.talk(down: true))
        _ = state.handle(.modifiers(shift: true, command: false))
        _ = state.handle(.talk(down: false))
        return state
    }

    @Test func holdAndReleaseFinishExactlyOnce() {
        var state = DictationShortcuts()
        #expect(state.handle(.talk(down: true)).action == .start)
        #expect(state.phase == .listening)
        #expect(!state.handsFree && !state.polish)
        #expect(state.handle(.talk(down: true)).action == nil)
        #expect(state.handle(.talk(down: false)).action == .finish)
        #expect(state.phase == .processing)
        #expect(state.handle(.talk(down: false)).action == nil)
    }

    @Test func shiftLatchesBeforeOrAfterTalkBegins() {
        for preheld in [false, true] {
            var state = DictationShortcuts()
            _ = state.handle(.modifiers(shift: true, command: false))
            #expect(!state.handsFree)
            _ = state.handle(.talk(down: true, shift: preheld))
            if !preheld { _ = state.handle(.modifiers(shift: true, command: false)) }
            _ = state.handle(.modifiers(shift: false, command: false))
            #expect(state.handsFree)
            #expect(state.handle(.talk(down: false)).action == nil)
            #expect(state.phase == .listening)
        }
    }

    @Test func shiftAfterOrdinaryReleaseCannotReopenUtterance() {
        var state = DictationShortcuts()
        _ = state.handle(.talk(down: true))
        _ = state.handle(.talk(down: false))
        _ = state.handle(.modifiers(shift: true, command: false))
        #expect(state.phase == .processing)
        #expect(!state.handsFree)
    }

    @Test func commandLatchesRegardlessOfReleaseOrder() {
        for commandReleasesFirst in [false, true] {
            var state = DictationShortcuts()
            _ = state.handle(.talk(down: true))
            _ = state.handle(.modifiers(shift: false, command: true))
            if commandReleasesFirst { _ = state.handle(.modifiers(shift: false, command: false)) }
            #expect(state.handle(.talk(down: false, command: !commandReleasesFirst)).action == .finish)
            #expect(state.polish)
        }
    }

    @Test func commandAlreadyHeldAndCommandOnReleaseAreRecognized() {
        for preheld in [true, false] {
            var state = DictationShortcuts()
            _ = state.handle(.talk(down: true, command: preheld))
            _ = state.handle(.talk(down: false, command: true))
            #expect(state.polish)
        }
    }

    @Test func commandDuringHandsFreeAfterTalkReleaseIsRecognized() {
        var state = handsFree()
        _ = state.handle(.modifiers(shift: false, command: true))
        _ = state.handle(.modifiers(shift: false, command: false))
        #expect(state.polish && state.handsFree)
        #expect(state.handle(.key(.return, down: true)).action == .finish)
        #expect(state.polish)
    }

    @Test func commandAfterFinishDoesNotChangeMode() {
        var state = DictationShortcuts()
        _ = state.handle(.talk(down: true))
        _ = state.handle(.talk(down: false))
        _ = state.handle(.modifiers(shift: false, command: true))
        #expect(!state.polish)
    }

    @Test(arguments: [DictationShortcuts.Key.return, .keypadEnter])
    func returnConsumesBothEdgesAndRepeats(_ key: DictationShortcuts.Key) {
        var state = handsFree()
        let down = state.handle(.key(key, down: true))
        #expect(down.action == .finish && down.swallow)
        #expect(state.phase == .processing)
        #expect(state.handle(.key(key, down: true)) == .init(action: nil, swallow: true))
        state.complete()
        #expect(state.handle(.key(key, down: true)).swallow)
        #expect(state.handle(.key(key, down: false)).swallow)
        #expect(!state.handle(.key(key, down: true)).swallow)
    }

    @Test func separateReturnKeysHaveSeparateReleasePairs() {
        var state = handsFree()
        _ = state.handle(.key(.return, down: true))
        _ = state.handle(.key(.keypadEnter, down: true))
        state.complete()
        #expect(state.handle(.key(.return, down: false)).swallow)
        #expect(state.handle(.key(.keypadEnter, down: false)).swallow)
    }

    @Test func secondFinishWhileProcessingIsIgnored() {
        var state = handsFree()
        _ = state.handle(.key(.return, down: true))
        _ = state.handle(.key(.return, down: false))
        #expect(state.handle(.key(.return, down: true)) == .init(action: nil, swallow: true))
        #expect(state.handle(.talk(down: true)).action == nil)
        #expect(state.handle(.talk(down: false)).action == nil)
        #expect(state.phase == .processing)
    }

    @Test func talkRepressFinishesAndItsReleaseCannotFinishAgain() {
        var state = handsFree()
        #expect(state.handle(.talk(down: true, command: true)).action == .finish)
        #expect(state.polish)
        state.complete()
        #expect(state.handle(.talk(down: true)).action == nil)
        #expect(state.handle(.talk(down: false)).action == nil)
        #expect(state.handle(.talk(down: true)).action == .start)
        #expect(!state.handsFree && !state.polish)
    }

    @Test func returnWhileTalkStillHeldFinishesOnce() {
        var state = DictationShortcuts()
        _ = state.handle(.talk(down: true, shift: true))
        #expect(state.handle(.key(.return, down: true)).action == .finish)
        #expect(state.handle(.talk(down: false)).action == nil)
    }

    @Test(arguments: [false, true])
    func escapeCancelsListeningOrProcessing(_ processing: Bool) {
        var state = handsFree()
        if processing { _ = state.handle(.key(.return, down: true)) }
        #expect(state.handle(.key(.escape, down: true)) == .init(action: .cancel, swallow: true))
        #expect(state.phase == .idle)
        #expect(!state.polish && !state.handsFree)
        #expect(state.handle(.key(.escape, down: true)) == .init(action: nil, swallow: true))
        #expect(state.handle(.key(.escape, down: false)).swallow)
        if processing { #expect(state.handle(.key(.return, down: false)).swallow) }
        #expect(state.handle(.talk(down: true)).action == .start)
    }

    @Test func escapeWhileOriginalTalkHeldDoesNotRestartOnRelease() {
        var state = DictationShortcuts()
        _ = state.handle(.talk(down: true, shift: true, command: true))
        _ = state.handle(.key(.escape, down: true))
        #expect(state.handle(.talk(down: false)).action == nil)
        #expect(state.handle(.talk(down: true)).action == .start)
        #expect(!state.polish && !state.handsFree)
    }

    @Test(arguments: [DictationShortcuts.Key.return, .keypadEnter, .escape])
    func keysPassThroughOutsideHandsFree(_ key: DictationShortcuts.Key) {
        var state = DictationShortcuts()
        for phase in 0..<3 {
            if phase == 1 { _ = state.handle(.talk(down: true)) }
            if phase == 2 { _ = state.handle(.talk(down: false)) }
            #expect(state.handle(.key(key, down: true)) == .init(action: nil, swallow: false))
            #expect(state.handle(.key(key, down: false)) == .init(action: nil, swallow: false))
        }
    }

    @Test func specialKeyUpsAreSwallowedWhileHandsFreeIsActive() {
        var state = handsFree()
        #expect(state.handle(.key(.return, down: false)).swallow)
        #expect(state.handle(.key(.escape, down: false)).swallow)
    }

    @Test(arguments: [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]])
    func allChordPressAndReleaseOrders(_ order: [Int]) {
        for releaseOrder in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            var state = DictationShortcuts()
            var held = Set<Int>()
            for modifier in order {
                held.insert(modifier)
                if modifier == 0 {
                    #expect(state.handle(.talk(down: true, shift: held.contains(1), command: held.contains(2))).action == .start)
                } else {
                    _ = state.handle(.modifiers(shift: held.contains(1), command: held.contains(2)))
                }
            }
            for modifier in releaseOrder {
                held.remove(modifier)
                let event: DictationShortcuts.Event = modifier == 0
                    ? .talk(down: false, shift: held.contains(1), command: held.contains(2))
                    : .modifiers(shift: held.contains(1), command: held.contains(2))
                #expect(state.handle(event).action == nil)
            }
            #expect(state.phase == .listening && state.handsFree && state.polish)
            #expect(state.handle(.key(.return, down: true)).action == .finish)
        }
    }

    @Test func completionOrFailureClearsModesButRequiresTalkRelease() {
        var state = DictationShortcuts()
        _ = state.handle(.talk(down: true, shift: true, command: true))
        state.complete()
        #expect(state.phase == .idle)
        #expect(!state.handsFree && !state.polish)
        #expect(state.handle(.talk(down: true)).action == nil)
        #expect(state.handle(.talk(down: false)).action == nil)
        #expect(state.handle(.talk(down: true)).action == .start)
    }
}
