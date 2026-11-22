import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldAppearance: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let rule = application.token.flatMap { token in
            (try? RuleStore().read())?.first { $0.application == token }
        }
        let canGrantBonus = rule?.phase.canGrantBonus == true

        let navy = UIColor(red: 0.05, green: 0.09, blue: 0.18, alpha: 1)
        let mint = UIColor(red: 0.44, green: 0.95, blue: 0.76, alpha: 1)
        let subtitleColor = UIColor(red: 0.78, green: 0.84, blue: 0.91, alpha: 1)
        let icon = UIImage(
            systemName: "hourglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 52, weight: .semibold)
        )?.withTintColor(mint, renderingMode: .alwaysOriginal)

        return ShieldConfiguration(
            backgroundColor: navy,
            icon: icon,
            title: .init(text: "Time’s up", color: .white),
            subtitle: .init(
                text: canGrantBonus ? "One five-minute extension is available." : "This app is locked.",
                color: subtitleColor
            ),
            primaryButtonLabel: .init(text: "OK", color: navy),
            primaryButtonBackgroundColor: mint,
            secondaryButtonLabel: canGrantBonus ? .init(text: "+ 5 Minutes", color: mint) : nil
        )
    }
}
