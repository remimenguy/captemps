import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
struct BlockController {
    private let store = RuleStore()
    private let center = DeviceActivityCenter()

    static var isAuthorized: Bool {
        let status = AuthorizationCenter.shared.authorizationStatus
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return true }
        return status == .approved
    }

    func refresh() throws -> [BlockRule] {
        try requireAuthorization()
        return try store.withBonusLock {
            let activities = Set(center.activities)
            let now = Date()

            let rules = try store.update { rules in
                for index in rules.indices {
                    rules[index].resetIfNeeded(at: now)
                    switch rules[index].phase {
                    case .settingUpBonus:
                        // No other process can be setting up the bonus while this lock is held.
                        rules[index].phase.finishBonus()
                    case .bonus where !activities.contains(rules[index].bonusActivity):
                        rules[index].phase.finishBonus()
                    case .bonus:
                        rules[index].phase.expireBonus(at: now)
                    default:
                        break
                    }
                }
                return rules
            }

            for rule in rules where !activities.contains(rule.dailyActivity) {
                try startDaily(rule)
            }
            let needed = Set(rules.map(\.dailyActivity) + rules.compactMap { rule in
                if case .bonus = rule.phase { return rule.bonusActivity }
                return nil
            })
            let obsolete = activities.subtracting(needed)
            if !obsolete.isEmpty { center.stopMonitoring(Array(obsolete)) }
            return rules
        }
    }

    func add(application: ApplicationToken, minutes: Int) throws {
        guard (0...1439).contains(minutes) else { throw RuleError.invalidLimit }
        _ = try refresh()
        let rule = BlockRule(application: application, dailyMinutes: minutes)
        try store.update { rules in
            guard !rules.contains(where: { $0.application == application }) else {
                throw RuleError.alreadyConfigured
            }
            guard rules.count < 20 else { throw RuleError.tooManyRules }
            rules.append(rule)
        }
        do {
            try startDaily(rule)
        } catch {
            try store.update { rules in
                rules.removeAll { $0.id == rule.id }
            }
            throw error
        }
    }

    private func startDaily(_ rule: BlockRule) throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent]
        if rule.dailyMinutes == 0 {
            events = [:]
        } else {
            events = [BlockRule.dailyLimitEvent: DeviceActivityEvent(
                applications: [rule.application],
                threshold: DateComponents(minute: rule.dailyMinutes),
                includesPastActivity: true
            )]
        }
        try center.startMonitoring(rule.dailyActivity, during: schedule, events: events)
    }

    func grantBonus(for application: ApplicationToken) throws {
        try requireAuthorization()
        try BonusController().grant(for: application)
    }

    private func requireAuthorization() throws {
        guard Self.isAuthorized else { throw RuleError.authorizationRequired }
    }
}
