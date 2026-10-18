import Foundation

/// Retains the original across presets and checks that a result still owns its insertion point.
public struct SelectionRewrite: Codable, Sendable, Equatable {
    public struct Position: Codable, Sendable, Equatable {
        public var documentID: UUID
        public var before: String?
        public var after: String?
        public var selection: String?

        public init(documentID: UUID, before: String?, after: String?, selection: String?) {
            self.documentID = documentID
            self.before = before
            self.after = after
            self.selection = selection
        }
    }

    public let original: String
    public let documentID: UUID
    public private(set) var result: String?
    public private(set) var position: Position?
    public private(set) var undoUntil: Date?
    public private(set) var target: Position?
    public private(set) var flight: Flight?
    public private(set) var failed: Bool?

    public struct Flight: Codable, Sendable, Equatable {
        public let id: UUID
        public let startedAt: Date
        public let preset: String
        public let path: String
    }

    public enum Refusal: String, Sendable {
        case disconnected, documentChanged, unverifiedTarget, selectionChanged, contextChanged
        case requestChanged, timeout, emptyResult, undoExpired, interveningChange, truncatedContext, graphemeBoundary
    }

    public enum Replacement: Equatable, Sendable {
        case replaced(Int)
        case refused(Refusal)
    }

    public static let noDocument = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    public init(original: String, documentID: UUID) {
        self.original = original
        self.documentID = documentID
    }

    public init(original: String, at position: Position) {
        self.original = original
        documentID = position.documentID
        target = position
    }

    /// A persisted cursor snapshot alone cannot prove ownership of a replacement range.
    public func refusal(at current: Position, unchangedInsertion: Bool = false) -> Refusal? {
        guard current.documentID != Self.noDocument else { return .disconnected }
        guard current.documentID == documentID else { return .documentChanged }
        guard let target else { return .unverifiedTarget }
        if let selection = current.selection, !selection.isEmpty {
            guard selection == (result ?? original) else { return .selectionChanged }
            guard current.before == target.before, current.after == target.after else { return .contextChanged }
            return nil
        }
        guard let result, let position else { return .selectionChanged }
        guard position.documentID == current.documentID else { return .documentChanged }
        guard unchangedInsertion else { return .interveningChange }
        guard let before = current.before, before.count >= result.count else { return .truncatedContext }
        guard before.hasSuffix(result) else { return .contextChanged }
        guard String(before.suffix(result.count)) == result else { return .graphemeBoundary }
        if let after = current.after, (before + after).count != before.count + after.count {
            return .graphemeBoundary
        }
        guard let savedBefore = position.before,
              before.hasSuffix(savedBefore) || savedBefore.hasSuffix(before),
              Self.matchesAfter(current.after, position.after) else { return .contextChanged }
        return nil
    }

    private static func matchesAfter(_ current: String?, _ saved: String?) -> Bool {
        switch (current, saved) {
        case (nil, nil): true
        case let (current?, saved?):
            current.isEmpty == saved.isEmpty && (current.hasPrefix(saved) || saved.hasPrefix(current))
        default: false
        }
    }

    @discardableResult
    public mutating func begin(id: UUID, preset: String, path: String, now: Date) -> Bool {
        guard flight == nil else { return false }
        flight = Flight(id: id, startedAt: now, preset: preset, path: path)
        failed = false
        return true
    }

    @discardableResult
    public mutating func fail(id: UUID) -> Bool {
        guard flight?.id == id else { return false }
        flight = nil
        failed = true
        return true
    }

    /// Validation and replacement are synchronous on the UI actor. Collapsed replacements
    /// require the entire result, its surrounding context, and an uninterrupted edit history.
    @MainActor
    public mutating func apply(_ text: String, id: UUID, to document: any SelectionRewriteDocument,
                               now: Date) -> Replacement {
        guard let flight, flight.id == id else { return .refused(.requestChanged) }
        defer { self.flight = nil }
        failed = true
        guard now.timeIntervalSince(flight.startedAt) < 20 else { return .refused(.timeout) }
        guard !text.isEmpty else { return .refused(.emptyResult) }
        let current = document.rewritePosition
        if let reason = refusal(at: current, unchangedInsertion: document.unchangedInsertion) {
            return .refused(reason)
        }
        let count = (current.selection ?? "").isEmpty ? result?.count ?? 0 : 0
        document.replaceVerifiedText(text, deletingCharacters: count)
        didInsert(text, at: document.rewritePosition, now: now)
        return .replaced(text.count)
    }

    @MainActor
    public mutating func undo(in document: any SelectionRewriteDocument, now: Date) -> Replacement {
        guard flight == nil else { return .refused(.requestChanged) }
        guard result != nil, undoUntil.map({ now < $0 }) == true else { return .refused(.undoExpired) }
        let current = document.rewritePosition
        if let reason = refusal(at: current, unchangedInsertion: document.unchangedInsertion) {
            return .refused(reason)
        }
        let count = (current.selection ?? "").isEmpty ? result?.count ?? 0 : 0
        document.replaceVerifiedText(original, deletingCharacters: count)
        result = original
        undoUntil = nil
        position = document.rewritePosition
        failed = false
        return .replaced(original.count)
    }

    /// Presentation only; apply/undo additionally require uninterrupted edit history.
    public func canReplace(at current: Position) -> Bool {
        guard current.documentID == documentID else { return false }
        if let selection = current.selection, !selection.isEmpty {
            return selection == (result ?? original)
        }
        return result != nil && position == current
    }

    public func canUndo(at current: Position, now: Date) -> Bool {
        canReplace(at: current) && result != nil && (undoUntil.map { now < $0 } ?? false)
    }

    public mutating func didInsert(_ text: String, at position: Position, now: Date) {
        result = text
        self.position = position
        undoUntil = now.addingTimeInterval(10)
        failed = false
    }

    /// Committing our marked range moves the caret without granting a fresh Undo window.
    public mutating func didCommitMarkedResult(at position: Position) {
        guard result != nil, position.documentID == documentID else { return }
        self.position = position
    }
}

@MainActor
public protocol SelectionRewriteDocument: AnyObject {
    var rewritePosition: SelectionRewrite.Position { get }
    var unchangedInsertion: Bool { get }
    func replaceVerifiedText(_ text: String, deletingCharacters: Int)
}
