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
        let activities = Set(center.activities)
        let now = Date()

        let rules = try store.update { rules in
            for index in rules.indices {
                switch rules[index].phase {
                case .tracking where !activities.contains(rules[index].dailyActivity):
                    rules[index].phase.reachLimit()
                case .settingUpBonus:
                    // Setup runs synchronously on the main actor. Finding it here means it was interrupted.
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
            try start(rule.dailyActivity, schedule: schedule, event: BlockRule.dailyLimitEvent,
                      application: application, minutes: minutes)
        } catch {
            try store.update { rules in
                rules.removeAll { $0.id == rule.id && $0.phase == .tracking }
            }
            throw error
        }
    }

    func grantBonus(for id: UUID) throws {
        _ = try refresh()
        let now = Date()
        let until = now.addingTimeInterval(24 * 60 * 60)
        let rule = try store.update { rules in
            guard let index = rules.firstIndex(where: { $0.id == id }),
                  rules[index].phase.beginBonus(until: until) else {
                throw RuleError.bonusUnavailable
            }
            return rules[index]
        }

        // Use a single window across midnight. Keep the shield up until monitoring is registered.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components: Set<Calendar.Component> = [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: now.addingTimeInterval(-1)),
            intervalEnd: calendar.dateComponents(components, from: until),
            repeats: false
        )
        do {
            try start(rule.bonusActivity, schedule: schedule, event: BlockRule.bonusLimitEvent,
                      application: rule.application, minutes: BlockRule.bonusMinutes)
        } catch {
            try store.update { rules in
                if let index = rules.firstIndex(where: { $0.id == id }) {
                    rules[index].phase.cancelBonusSetup()
                }
            }
            throw error
        }

        try store.update { rules in
            if let index = rules.firstIndex(where: { $0.id == id }) {
                rules[index].phase.activateBonus()
            }
        }
    }

    private func requireAuthorization() throws {
        guard Self.isAuthorized else { throw RuleError.authorizationRequired }
    }

    private func start(
        _ activity: DeviceActivityName,
        schedule: DeviceActivitySchedule,
        event: DeviceActivityEvent.Name,
        application: ApplicationToken,
        minutes: Int
    ) throws {
        try center.startMonitoring(activity, during: schedule, events: [
            event: DeviceActivityEvent(
                applications: [application],
                threshold: DateComponents(minute: minutes),
                includesPastActivity: false
            )
        ])
    }
}
