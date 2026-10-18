import Foundation

public struct MeetingSpeaker: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct MeetingTurn: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var speakerID: String
    public var start: Double
    public var end: Double
    public var text: String
    public var isEdited: Bool
    public init(id: UUID = UUID(), speakerID: String, start: Double, end: Double, text: String, isEdited: Bool = false) {
        self.id = id; self.speakerID = speakerID; self.start = start; self.end = end; self.text = text; self.isEdited = isEdited
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        speakerID = try container.decode(String.self, forKey: .speakerID)
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        text = try container.decode(String.self, forKey: .text)
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
    }
}

public struct MeetingAction: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    public var owner: String?
    public var done: Bool
    public init(id: UUID = UUID(), text: String, owner: String? = nil, done: Bool = false) {
        self.id = id; self.text = text; self.owner = owner; self.done = done
    }
}

public struct MeetingSummary: Codable, Sendable, Equatable {
    public var bullets: [String]
    public var actions: [MeetingAction]
    public init(bullets: [String], actions: [MeetingAction] = []) { self.bullets = bullets; self.actions = actions }
}

/// Persisted so a launch after a crash or force-quit knows which meetings still need their
/// audio turned into a transcript.
public enum MeetingRecordingState: String, Codable, Sendable {
    case recording, processing, done
}

/// One audio file of a recording. A stream can span several files when capture restarts
/// (device change, sleep); each file carries its own offset from the meeting start.
public struct MeetingAudioSegment: Codable, Sendable, Hashable {
    public static let microphone = "you"
    public static let system = "system"
    public var stream: String
    public var file: String
    public var offset: Double
    public init(stream: String, file: String, offset: Double) {
        self.stream = stream; self.file = file; self.offset = offset
    }
}

public struct Meeting: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var modified: Date
    public var deletedAt: Date?
    /// A recording owns its retention choice so changing defaults only affects future meetings.
    public var retainsAudio: Bool?
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var duration: Double
    public var speakers: [MeetingSpeaker]
    public var turns: [MeetingTurn]
    public var summary: MeetingSummary?
    public var notes: String
    public var pinned: Bool
    public var recovered: Bool
    public var appName: String?
    public var processingError: String?
    public var summaryError: String?
    public var summaryNeedsUpdate = false
    public var transcriptionRetryPending = false
    public var summaryRetryPending = false
    public var state: MeetingRecordingState
    /// Dictation languages at recording time; the spoken one is chosen when processing.
    public var languages: [String]
    public var audio: [MeetingAudioSegment]
    public init(id: UUID = UUID(), title: String, startedAt: Date = .now, endedAt: Date? = nil,
                duration: Double = 0, speakers: [MeetingSpeaker] = [], turns: [MeetingTurn] = [],
                summary: MeetingSummary? = nil, appName: String? = nil, state: MeetingRecordingState = .done,
                languages: [String] = [], audio: [MeetingAudioSegment] = [], notes: String = "", recovered: Bool = false, pinned: Bool = false, retainsAudio: Bool? = nil) {
        self.retainsAudio = retainsAudio
        self.modified = startedAt
        self.id = id; self.title = title; self.startedAt = startedAt; self.endedAt = endedAt
        self.duration = duration; self.speakers = speakers; self.turns = turns; self.summary = summary
        self.notes = notes; self.recovered = recovered; self.pinned = pinned
        self.appName = appName; self.state = state; self.languages = languages; self.audio = audio
    }
    /// Files written before recording state existed describe finished meetings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        modified = try container.decodeIfPresent(Date.self, forKey: .modified) ?? startedAt
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        retainsAudio = try container.decodeIfPresent(Bool.self, forKey: .retainsAudio)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        duration = try container.decode(Double.self, forKey: .duration)
        speakers = try container.decode([MeetingSpeaker].self, forKey: .speakers)
        turns = try container.decode([MeetingTurn].self, forKey: .turns)
        summary = try container.decodeIfPresent(MeetingSummary.self, forKey: .summary)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        recovered = try container.decodeIfPresent(Bool.self, forKey: .recovered) ?? false
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        processingError = try container.decodeIfPresent(String.self, forKey: .processingError)
        summaryError = try container.decodeIfPresent(String.self, forKey: .summaryError)
        summaryRetryPending = try container.decodeIfPresent(Bool.self, forKey: .summaryRetryPending) ?? false
        transcriptionRetryPending = try container.decodeIfPresent(Bool.self, forKey: .transcriptionRetryPending) ?? false
        summaryNeedsUpdate = try container.decodeIfPresent(Bool.self, forKey: .summaryNeedsUpdate) ?? false
        state = try container.decodeIfPresent(MeetingRecordingState.self, forKey: .state) ?? .done
        languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? []
        audio = try container.decodeIfPresent([MeetingAudioSegment].self, forKey: .audio) ?? []
    }
    public mutating func editTurn(_ id: UUID, text: String) {
        guard let index = turns.firstIndex(where: { $0.id == id }), turns[index].text != text else { return }
        turns[index].text = text
        turns[index].isEdited = true
        summaryNeedsUpdate = true
    }
    public func shouldKeepAudio(fallback: Bool) -> Bool {
        retainsAudio ?? (state == .done && !turns.isEmpty && !audio.isEmpty ? true : fallback)
    }
    public var needsRecovery: Bool { state != .done }
    public func speakerName(_ id: String) -> String { speakers.first { $0.id == id }?.name ?? id }
    public mutating func renameSpeaker(_ id: String, to name: String) {
        guard let index = speakers.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        speakers[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum MeetingTime {
    public static func stamp(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
