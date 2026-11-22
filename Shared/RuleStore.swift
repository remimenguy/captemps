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
    private let settings = ManagedSettingsStore(named: .init("CapTemps"))

    func update<Result>(_ change: (inout [BlockRule]) throws -> Result) throws -> Result {
        guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "CapTempsAppGroup") as? String,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw RuleError.sharedStorageUnavailable
        }

        // iOS can run the monitor and app together. Serialize disk and shield changes.
        let lockURL = folder.appendingPathComponent("rules.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw currentPOSIXError() }

        let rulesURL = folder.appendingPathComponent("rules.json")
        let previous: [BlockRule]
        do {
            previous = try JSONDecoder().decode([BlockRule].self, from: Data(contentsOf: rulesURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            previous = []
        }

        var rules = previous
        let result = try change(&rules)
        if rules != previous {
            try JSONEncoder().encode(rules).write(
                to: rulesURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        }
        let applications = Set(rules.filter(\.phase.isShielded).map(\.application))
        let shield: Set<ApplicationToken>? = applications.isEmpty ? nil : applications
        if settings.shield.applications != shield {
            settings.shield.applications = shield
        }
        return result
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
