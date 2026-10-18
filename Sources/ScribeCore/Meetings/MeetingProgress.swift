import Foundation

/// Each stage owns its result so a later failure does not hide work that already succeeded.
public struct MeetingProgress: Equatable, Sendable {
    public enum Step: String, CaseIterable, Identifiable, Sendable {
        case saving = "Saving audio", transcribing = "Transcribing"
        case speakers = "Identifying speakers", summarising = "Summarising"
        public var id: Self { self }
    }
    public enum Status: Equatable, Sendable { case pending, active, done, failed(String) }
    public init(identifiesSpeakers: Bool, statuses: [Step: Status] = [.saving: .active]) {
        self.identifiesSpeakers = identifiesSpeakers; self.statuses = statuses
    }
    public var identifiesSpeakers: Bool
    public var statuses: [Step: Status] = [.saving: .active]
    public var steps: [Step] { Step.allCases.filter { $0 != .speakers || identifiesSpeakers } }
    public subscript(_ step: Step) -> Status {
        get { statuses[step] ?? .pending }
        set { statuses[step] = newValue }
    }
}
