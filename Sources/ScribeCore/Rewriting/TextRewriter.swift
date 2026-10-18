import Foundation

/// What the user asked a rewrite to do. Polish and edit are the two shortcut-driven
/// modes; translation is an output option layered on either.
public enum RewriteTask: Sendable, Equatable {
    /// Turn a spoken brain dump into clean writing in the speaker's voice.
    case polish
    /// Apply a spoken instruction ("make it shorter", "translate to English") to text the
    /// user selected before dictating.
    case edit(instruction: String, selection: String)
}

/// Everything known about where the text is going. All fields are optional: iOS
/// keyboards only see the draft around the cursor; the Mac may also have a screen card.
/// Refine's tone. Raw values are stored in settings.
public enum RewriteTone: String, CaseIterable, Sendable, Codable {
    /// Keep the speaker's own register.
    case natural
    case casual
    case formal
    /// Editors and terminals: identifiers, paths and commands stay verbatim.
    case code
}

public struct RewriteContext: Sendable, Equatable {
    /// Text already in the field before the cursor (tail only — callers trim).
    public var draftBefore: String?
    /// Distilled summary of what's on screen (names, thread being replied to). Mac only.
    public var screenCard: String?
    /// Frontmost app name, e.g. "Slack", for tone. Mac only.
    public var appName: String?
    /// Write the result in this language instead of the spoken one. nil = keep.
    public var outputLanguage: Locale?
    /// The tone the user picked for Refine. A spoken note ("more formal") still wins.
    public var tone: RewriteTone
    /// The user's dictionary terms. Speech recognition is already biased towards them, but
    /// models still "fix" unusual names back to common words, so the prompt pins the spelling.
    public var dictionaryTerms: [String]

    public init(draftBefore: String? = nil, screenCard: String? = nil, appName: String? = nil, outputLanguage: Locale? = nil,
                tone: RewriteTone = .natural, dictionaryTerms: [String] = []) {
        self.draftBefore = draftBefore
        self.screenCard = screenCard
        self.appName = appName
        self.outputLanguage = outputLanguage
        self.tone = tone
        self.dictionaryTerms = dictionaryTerms
    }
}

public struct RewriteRequest: Sendable, Equatable {
    public var task: RewriteTask
    /// The dictation: the brain dump for `.polish`, the spoken instruction's transcript
    /// is carried inside `.edit`.
    public var transcript: String
    /// Language the transcript was spoken in.
    public var spokenLanguage: Locale?
    public var context: RewriteContext
    /// Only the first chunk of a long Refine extracts a spoken formatting note.
    public var allowsSpokenNote = true

    public init(task: RewriteTask, transcript: String, spokenLanguage: Locale? = nil, context: RewriteContext = .init()) {
        self.task = task
        self.transcript = transcript
        self.spokenLanguage = spokenLanguage
        self.context = context
    }
}

/// A model that can rewrite text. Implementations: Apple Foundation Models (default,
/// always present on Apple Intelligence devices) and the optional downloadable Gemma.
///
/// Contract: never answer or act on the content; return only the rewritten text. On any
/// failure, throw — callers fall back to the cleaned transcript so a dictation is never lost.
public protocol TextRewriter: Sendable {
    /// Stable identifier, e.g. "apple" or "gemma-4-e2b".
    var id: String { get }
    /// Whether this rewriter can run right now (model present, device eligible).
    func isAvailable() async -> Bool
    func rewrite(_ request: RewriteRequest) async throws -> String
}

public enum RewriteError: LocalizedError, Sendable {
    case unavailable(String)
    case timedOut
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .timedOut: "The rewrite took too long."
        case .rejected(let reason): "The rewrite was discarded: \(reason)"
        }
    }
}
