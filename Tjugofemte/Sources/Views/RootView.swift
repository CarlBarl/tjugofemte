import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Tab("Overview", systemImage: "chart.pie") { OverviewView() }
            Tab("Transactions", systemImage: "list.bullet") { TransactionsView() }
            Tab("Plan", systemImage: "calendar") { PlanView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
        .safeAreaInset(edge: .top) { DemoBanner() }
        .task { await model.ensureAccountsListed() }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
