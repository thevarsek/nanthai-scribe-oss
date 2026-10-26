import AppKit
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
    func previewEnabled(_ value: Bool, names: [String] = []) { enabled = value; self.names = value ? names : [] }
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

    /// Off means off: no names are held and nothing is matched. `languages` are the dictation
    /// languages, whose ordinary words a name may never replace.
    func matches(in text: String, languages: [String]) -> [DictionaryEntry] {
        guard enabled, !names.isEmpty else { return [] }
        let dictionaries = Self.spellLanguages(for: languages, available: NSSpellChecker.shared.availableLanguages)
        return NameMatcher.matches(in: text, names: names) { Self.isWord($0, in: dictionaries) }
    }

    /// An ordinary word in any of the dictionaries. Lowercase is what makes "julia" a misspelling
    /// while "and" stays a word.
    static func isWord(_ word: String, in dictionaries: [String]) -> Bool {
        guard !word.isEmpty else { return false }
        let checker = NSSpellChecker.shared
        return dictionaries.contains { language in
            checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                  inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
    }

    /// The spell checker's dictionary for each dictation language, exact region first.
    nonisolated static func spellLanguages(for languages: [String], available: [String]) -> [String] {
        var chosen: [String] = []
        for identifier in languages {
            let wanted = identifier.replacingOccurrences(of: "-", with: "_")
            let code = String(wanted.prefix { $0 != "_" })
            let match = available.first { $0 == wanted } ?? available.first { $0 == code }
                ?? available.first { $0.hasPrefix(code + "_") }
            if let match, !chosen.contains(match) { chosen.append(match) }
        }
        return chosen
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
