import Darwin
import Foundation
import ManagedSettings

enum RuleError: LocalizedError {
    case sharedStorageUnavailable
    case invalidLimit
    case alreadyConfigured
    case tooManyRules
    case bonusUnavailable
    case authorizationRequired

    var errorDescription: String? {
        switch self {
        case .sharedStorageUnavailable: "The shared Screen Time storage is unavailable."
        case .invalidLimit: "Enter a duration between 0 and 1,439 minutes."
        case .alreadyConfigured: "This app already has a locked rule."
        case .tooManyRules: "CapTemps can protect up to 20 apps."
        case .bonusUnavailable: "The extension is no longer available for this app."
        case .authorizationRequired: "Allow CapTemps to access Screen Time."
        }
    }
}

struct RuleStore {
    func read() throws -> [BlockRule] {
        // Writers replace the file atomically, so a reader always sees a complete snapshot.
        try loadRules(from: container().appendingPathComponent("rules.json"))
    }

    func withBonusLock<Result>(_ operation: () throws -> Result) throws -> Result {
        let folder = try container()
        // The app can refresh while the shield action schedules a bonus. Monitor callbacks
        // still need the rules lock during that operation, so use a separate lock here.
        return try withLock(at: folder.appendingPathComponent("bonus.lock"), operation)
    }

    func update<Result>(_ change: (inout [BlockRule]) throws -> Result) throws -> Result {
        let folder = try container()
        return try withLock(at: folder.appendingPathComponent("rules.lock")) {
            let rulesURL = folder.appendingPathComponent("rules.json")
            let previous = try loadRules(from: rulesURL)

            var rules = previous
            let result = try change(&rules)
            if rules != previous {
                try JSONEncoder().encode(rules).write(
                    to: rulesURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            }
            let applications = Set(rules.filter(\.phase.isShielded).map(\.application))
            let shield: Set<ApplicationToken>? = applications.isEmpty ? nil : applications
            let settings = ManagedSettingsStore(named: .init("CapTemps"))
            if settings.shield.applications != shield {
                settings.shield.applications = shield
            }
            return result
        }
    }

    private func container() throws -> URL {
        guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "CapTempsAppGroup") as? String,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw RuleError.sharedStorageUnavailable
        }
        return folder
    }

    private func loadRules(from url: URL) throws -> [BlockRule] {
        do {
            return try JSONDecoder().decode([BlockRule].self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    private func withLock<Result>(at url: URL, _ operation: () throws -> Result) throws -> Result {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw currentPOSIXError() }
        return try operation()
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
