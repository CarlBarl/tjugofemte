import SwiftUI

/// What the app shows until it has something to show: the welcome, the bank wizard, then the plan setup.
/// Two separate stacks, so the pushed bank screens vanish the moment the account is chosen.
struct StartFlow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.stage == .ready {
            NavigationStack { PlanSetupView(mode: .firstRun).toolbar(.hidden, for: .navigationBar).statusBarInk() }
                .tint(Tokens.accent)
        } else {
            NavigationStack { WelcomeView().toolbar(.hidden, for: .navigationBar).statusBarInk() }
                .tint(Tokens.accent)
        }
    }
}

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var connecting = false

    var body: some View {
        VStack(spacing: 0) {
            Screen(spacing: 24) {
                Spacer().frame(height: 32)
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Tjugofemte")
                    Text("One number on payday.").appFont(size: 40, weight: .bold, rounded: true).foregroundStyle(Tokens.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("How much to move to savings, worked out from your own bank data. It never leaves your phone.")
                        .appFont(size: 17).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        feature("building.columns", "Your bank, your key", "You register the connection yourself. No company sits in between.")
                        Hairline()
                        feature("calendar", "Payday to payday", "Income and budgets per salary period, not per calendar month.")
                        Hairline()
                        feature("trash", "Gone when you say so", "Delete everything with one tap. Export a CSV first if you like.")
                    }
                }
            }
            VStack(spacing: 4) {
                BigButton(title: model.stage == .needsKey ? "Connect my bank" : "Continue setup") { connecting = true }
                TextAction(title: "Try with sample data", systemImage: "sparkles") { model.startDemo() }
            }
            .padding(.horizontal, Tokens.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Tokens.bg)
        .navigationDestination(isPresented: $connecting) {
            if model.stage == .needsAccount { AccountPickerView() } else { OnboardingView() }
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryGlyph(symbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).appFont(size: 16, weight: .semibold).foregroundStyle(Tokens.text)
                Text(text).appFont(size: 14).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
