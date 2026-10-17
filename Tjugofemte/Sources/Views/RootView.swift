import SwiftUI

/// The start flow until the app has something to show, the four tabs after that.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isSetUp {
                TabView {
                    Tab("Overview", systemImage: "chart.pie") { OverviewView() }
                    Tab("Transactions", systemImage: "list.bullet") { TransactionsView() }
                    Tab("Plan", systemImage: "slider.horizontal.3") { PlanView() }
                    Tab("Settings", systemImage: "gearshape") { SettingsView() }
                }
            } else {
                StartFlow()
            }
        }
        .tint(Tokens.accent)
        .task { await model.ensureAccountsListed() }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
