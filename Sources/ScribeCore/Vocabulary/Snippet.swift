import Foundation

public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var trigger: String
    public var text: String
    public var modified: Date

    public init(id: UUID = UUID(), trigger: String = "", text: String = "", modified: Date = .now) {
        self.id = id
        self.trigger = trigger
        self.text = text
        self.modified = modified
    }

    private enum CodingKeys: String, CodingKey { case id, trigger, text, modified }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        trigger = try values.decode(String.self, forKey: .trigger)
        text = try values.decode(String.self, forKey: .text)
        modified = try values.decodeIfPresent(Date.self, forKey: .modified)
            ?? decoder.userInfo[.vocabularyMigrationDate] as? Date ?? .now
    }
}

extension CodingUserInfoKey {
    static let vocabularyMigrationDate = CodingUserInfoKey(rawValue: "vocabularyMigrationDate")!
}
