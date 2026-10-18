/// Logical shortcut events, independent of the event tap and audio lifecycle. Kept in
/// the Mac support target because the hold/chord interaction is specific to the Mac.
public struct DictationShortcuts: Equatable, Sendable {
    public enum Phase: Sendable { case idle, listening, processing }
    public enum Key: Hashable, Sendable { case `return`, keypadEnter, escape }
    public enum Event: Sendable {
        case talk(down: Bool, shift: Bool = false, command: Bool = false)
        case modifiers(shift: Bool, command: Bool)
        case key(Key, down: Bool)
    }
    public enum Action: Equatable, Sendable { case start, finish, cancel }
    public struct Result: Equatable, Sendable {
        public var action: Action?
        public var swallow: Bool
    }

    public private(set) var phase: Phase = .idle
    public private(set) var handsFree = false
    public private(set) var polish = false
    private var talkDown = false
    private var swallowed: Set<Key> = []

    public init() {}

    public mutating func handle(_ event: Event) -> Result {
        var action: Action?
        var swallow = false
        switch event {
        case .talk(let down, let shift, let command):
            guard down != talkDown else { return Result(swallow: false) }
            talkDown = down
            if down, phase == .idle {
                phase = .listening
                handsFree = shift
                polish = command
                action = .start
            } else if down, phase == .listening, handsFree {
                polish = polish || command
                phase = .processing
                action = .finish
            } else if !down, phase == .listening {
                polish = polish || command
                if !handsFree {
                    phase = .processing
                    action = .finish
                }
            }
        case .modifiers(let shift, let command):
            if phase == .listening {
                handsFree = handsFree || (talkDown && shift)
                polish = polish || command
            }
        case .key(let key, let down):
            if !down {
                // Complete a consumed pair even if finishing/cancelling hid the HUD.
                swallow = swallowed.remove(key) != nil || (handsFree && phase != .idle)
            } else if swallowed.contains(key) {
                swallow = true // Autorepeat must never finish twice or escape to the app.
            } else if handsFree, phase != .idle {
                swallowed.insert(key)
                swallow = true
                if key == .escape {
                    complete()
                    action = .cancel
                } else if phase == .listening {
                    phase = .processing
                    action = .finish
                }
            }
        }
        return Result(action: action, swallow: swallow)
    }

    /// Preserve physical key state until release, including after an async completion.
    public mutating func complete() {
        phase = .idle
        handsFree = false
        polish = false
    }
}
