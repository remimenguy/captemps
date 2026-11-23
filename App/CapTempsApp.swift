import FamilyControls
import ManagedSettings
import SwiftUI

@main
struct CapTempsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var authorization = AuthorizationCenter.shared
    @State private var rules: [BlockRule] = []
    @State private var selection = FamilyActivitySelection()
    @State private var limit = "15"
    @State private var showPicker = false
    @State private var confirmRule = false
    @State private var requestingAccess = false
    @State private var errorMessage: String?

    private let controller = BlockController()

    private var selectedApp: ApplicationToken? {
        guard selection.categoryTokens.isEmpty, selection.webDomainTokens.isEmpty,
              selection.applicationTokens.count == 1 else { return nil }
        return selection.applicationTokens.first
    }

    private var minutes: Int? {
        guard let value = Int(limit), (0...1439).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                if BlockController.isAuthorized {
                    addRuleSection
                    rulesSection
                } else {
                    authorizationSection
                }
                protectionSection
            }
            .navigationTitle("CapTemps")
            .familyActivityPicker(isPresented: $showPicker, selection: $selection)
            .confirmationDialog("Lock this rule?", isPresented: $confirmRule, titleVisibility: .visible) {
                Button("Lock Rule", action: addRule)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This rule will remain active every day. You can add five minutes once each day after the app is blocked.")
            }
            .alert("CapTemps", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: authorization.authorizationStatus, initial: true) { refresh() }
            .onChange(of: scenePhase) { if scenePhase == .active { refresh() } }
        }
    }

    private var authorizationSection: some View {
        Section("Screen Time Access") {
            Button {
                Task {
                    requestingAccess = true
                    defer { requestingAccess = false }
                    do {
                        try await authorization.requestAuthorization(for: .individual)
                        refresh()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                if requestingAccess {
                    ProgressView()
                } else {
                    Text("Allow CapTemps")
                }
            }
            .disabled(requestingAccess)
        }
    }

    private var addRuleSection: some View {
        Section {
            Button {
                showPicker = true
            } label: {
                if let selectedApp {
                    Label(selectedApp)
                } else {
                    Text("Choose an App")
                }
            }

            TextField("Minutes per day", text: $limit)
                .keyboardType(.numberPad)
                .accessibilityLabel("Daily limit in minutes")

            Button("Lock Rule") {
                confirmRule = true
            }
            .disabled(selectedApp == nil || minutes == nil)
        } header: {
            Text("New Rule")
        } footer: {
            Text("Choose one app at a time. The limit resets every day. Enter 0 minutes to block immediately.")
        }
    }

    private var rulesSection: some View {
        Section("My Apps") {
            if rules.isEmpty {
                Text("No active rules")
                    .foregroundStyle(.secondary)
            }
            ForEach(rules) { rule in
                VStack(alignment: .leading, spacing: 6) {
                    Label(rule.application)
                    Text(status(for: rule))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if rule.phase.canGrantBonus {
                        Button("+ 5 minutes") { grantBonus(for: rule.application) }
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var protectionSection: some View {
        Section {
            DisclosureGroup("Protect Against Deletion") {
                Text("In Settings → Screen Time, lock your settings with a Screen Time passcode. Under Content & Privacy Restrictions → iTunes & App Store Purchases → Deleting Apps, select Don’t Allow.")
                Text("This setting prevents deletion of all apps. With individual authorization, you can still revoke the app’s Screen Time access in iOS Settings.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addRule() {
        guard let application = selectedApp, let minutes else { return }
        perform {
            if Application(token: application).bundleIdentifier == Bundle.main.bundleIdentifier {
                errorMessage = "Choose an app other than CapTemps."
                return
            }
            try controller.add(application: application, minutes: minutes)
            selection = FamilyActivitySelection()
        }
    }

    private func grantBonus(for application: ApplicationToken) {
        perform { try controller.grantBonus(for: application) }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() {
        guard BlockController.isAuthorized else {
            rules = []
            return
        }
        do {
            rules = try controller.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func status(for rule: BlockRule) -> String {
        switch rule.phase {
        case .tracking: "\(rule.dailyMinutes) min per day"
        case .blocked: "Blocked · one extension available"
        case .settingUpBonus: "Setting up the extension"
        case .bonus: "Extension active · 5 minutes of use within 24 hours"
        case .locked: "Blocked until tomorrow"
        }
    }
}
