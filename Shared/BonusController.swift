import DeviceActivity
import Foundation
import ManagedSettings

struct BonusController {
    private let store = RuleStore()
    private let center = DeviceActivityCenter()

    func grant(for application: ApplicationToken) throws {
        try store.withBonusLock {
            let now = Date()
            let until = now.addingTimeInterval(24 * 60 * 60)
            let rule = try store.update { rules in
                guard let index = rules.firstIndex(where: { $0.application == application }),
                      rules[index].phase.beginBonus(until: until) else {
                    throw RuleError.bonusUnavailable
                }
                return rules[index]
            }

            // Keep the shield in place until monitoring for the five minutes is registered.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            let components: Set<Calendar.Component> = [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second]
            let schedule = DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(components, from: now.addingTimeInterval(-1)),
                intervalEnd: calendar.dateComponents(components, from: until),
                repeats: false
            )
            do {
                try center.startMonitoring(rule.bonusActivity, during: schedule, events: [
                    BlockRule.bonusLimitEvent: DeviceActivityEvent(
                        applications: [application],
                        threshold: DateComponents(minute: BlockRule.bonusMinutes),
                        includesPastActivity: false
                    )
                ])
            } catch {
                try store.update { rules in
                    guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
                    rules[index].phase.cancelBonusSetup()
                }
                throw error
            }

            try store.update { rules in
                guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
                rules[index].phase.activateBonus()
            }
        }
    }
}
