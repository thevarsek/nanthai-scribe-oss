import Contacts
import Foundation
import Observation
import ScribeCore

/// Permission is requested only by the opt-in toggle. Foreground refreshes never prompt.
@MainActor
@Observable
final class ContactsNames {
    private let defaults: UserDefaults
    private var generation = 0
    private(set) var enabled: Bool
    private(set) var names: [String] = []
    private(set) var failure: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "useContactNames")
        refresh()
    }

    #if DEBUG
    func previewEnabled(_ value: Bool) { enabled = value; names = [] }
    #endif

    func setEnabled(_ value: Bool) {
        generation += 1
        let expected = generation
        enabled = value
        defaults.set(value, forKey: "useContactNames")
        names = []; failure = nil
        guard value else { return }
        Task {
            do {
                guard try await CNContactStore().requestAccess(for: .contacts), enabled, generation == expected else {
                    if generation == expected { enabled = false; defaults.set(false, forKey: "useContactNames") }
                    return
                }
                await load(expected: expected)
            } catch {
                guard generation == expected else { return }
                enabled = false; defaults.set(false, forKey: "useContactNames")
                failure = "Couldn't read Contacts. Try again."
            }
        }
    }

    func refresh() {
        generation += 1
        names = []
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard enabled, status == .authorized else { return }
        let expected = generation
        Task { await load(expected: expected) }
    }

    func matches(in text: String) -> [DictionaryEntry] {
        guard enabled else { return [] }
        return NameMatcher.matches(in: text, names: names)
    }

    private func load(expected: Int) async {
        do {
            let loaded = try await Task.detached(priority: .utility) { try Self.readNames() }.value
            guard enabled, generation == expected else { return }
            names = loaded; failure = nil
        } catch {
            if generation == expected { failure = "Couldn't read Contacts. Try again." }
        }
    }

    private nonisolated static func readNames() throws -> [String] {
        let request = CNContactFetchRequest(keysToFetch: [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey] as [CNKeyDescriptor])
        var names = Set<String>()
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            for name in [contact.givenName, contact.familyName, contact.nickname] where !name.isEmpty { names.insert(name) }
        }
        return names.sorted()
    }
}
