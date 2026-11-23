import DeviceActivity
import Foundation
import ManagedSettings

struct BlockRule: Codable, Equatable, Identifiable {
    static let dailyLimitEvent = DeviceActivityEvent.Name("daily-limit")
    static let bonusLimitEvent = DeviceActivityEvent.Name("bonus-limit")
    static let bonusMinutes = 5

    let id: UUID
    let application: ApplicationToken
    let dailyMinutes: Int
    var phase: BlockPhase
    var lastReset: Date?

    mutating func resetIfNeeded(at now: Date) {
        guard let lastReset else {
            self.lastReset = now
            return
        }
        guard !Calendar.current.isDate(lastReset, inSameDayAs: now),
              now > lastReset else { return }
        phase = dailyMinutes == 0 ? .blocked : .tracking
        self.lastReset = now
    }

    var dailyActivity: DeviceActivityName { DeviceActivityName("daily-\(id.uuidString)") }
    var bonusActivity: DeviceActivityName { DeviceActivityName("bonus-\(id.uuidString)") }

    init(application: ApplicationToken, dailyMinutes: Int) {
        id = UUID()
        self.application = application
        self.dailyMinutes = dailyMinutes
        lastReset = Date()
        phase = dailyMinutes == 0 ? .blocked : .tracking
    }
}
