import Foundation
import ManagedSettings
import OSLog

final class ShieldActionHandler: ShieldActionDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CapTempsShieldAction", category: "shield")

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        // A default shield can also show OK as its primary button, so only the
        // explicit secondary action can spend the one-time extension.
        guard action == .secondaryButtonPressed else {
            completionHandler(.close)
            return
        }

        do {
            try BonusController().grant(for: application)
            completionHandler(.none)
        } catch {
            logger.error("Could not grant the extension. Error code \((error as NSError).code)")
            completionHandler(.defer)
        }
    }
}
