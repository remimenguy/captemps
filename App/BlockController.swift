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
                    switch rules[index].phase {
                    case .tracking where !activities.contains(rules[index].dailyActivity):
                        rules[index].phase.reachLimit()
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

            let needed = Set(rules.compactMap { rule -> DeviceActivityName? in
                switch rule.phase {
                case .tracking: rule.dailyActivity
                case .bonus: rule.bonusActivity
                default: nil
                }
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
        guard minutes > 0 else { return }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        do {
            try center.startMonitoring(rule.dailyActivity, during: schedule, events: [
                BlockRule.dailyLimitEvent: DeviceActivityEvent(
                    applications: [application],
                    threshold: DateComponents(minute: minutes),
                    includesPastActivity: false
                )
            ])
        } catch {
            try store.update { rules in
                rules.removeAll { $0.id == rule.id && $0.phase == .tracking }
            }
            throw error
        }
    }

    func grantBonus(for application: ApplicationToken) throws {
        try requireAuthorization()
        try BonusController().grant(for: application)
    }

    private func requireAuthorization() throws {
        guard Self.isAuthorized else { throw RuleError.authorizationRequired }
    }
}
