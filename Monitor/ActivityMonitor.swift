import DeviceActivity
import Foundation
import OSLog

final class ActivityMonitor: DeviceActivityMonitor {
    private let store = RuleStore()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CapTempsMonitor", category: "monitor")

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        do {
            try store.update { rules in
                guard let index = rules.firstIndex(where: { $0.dailyActivity == activity }) else { return }
                rules[index].resetIfNeeded(at: Date())
            }
        } catch {
            logger.error("Could not reset the daily limit. Error code \((error as NSError).code)")
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        switch event {
        case BlockRule.dailyLimitEvent:
            applyToRule(matching: { $0.dailyActivity == activity }) { $0.reachLimit() }
        case BlockRule.bonusLimitEvent:
            closeBonus(for: activity)
        default:
            break
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        closeBonus(for: activity)
    }

    private func closeBonus(for activity: DeviceActivityName) {
        applyToRule(matching: { $0.bonusActivity == activity }) { $0.finishBonus() }
    }

    private func applyToRule(
        matching matches: (BlockRule) -> Bool,
        _ change: (inout BlockPhase) -> Void
    ) {
        do {
            try store.update { rules in
                guard let index = rules.firstIndex(where: matches) else { return }
                change(&rules[index].phase)
            }
        } catch {
            logger.error("Could not apply the shield. Error code: \((error as NSError).code)")
        }
    }
}
