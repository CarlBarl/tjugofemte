import SwiftUI
import BudgetCore
import LocalStore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false
    @State private var csvURL: URL?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                bankSection
                periodSection
                dataSection
                Section {
                    Toggle("Sample data", isOn: Binding(get: { model.isDemo }, set: { $0 ? model.startDemo() : model.stopDemo() }))
                } footer: {
                    Text("Shows three periods of made-up Swedish transactions. Your real data is untouched.")
                }
                Section("About") {
                    NavigationLink("Your data, explained") { DataPageView() }
                    Link("Source code", destination: Links.repository)
                    Link("Privacy policy", destination: Links.privacy)
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete everything?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { Task { await model.deleteEverything() } }
            } message: {
                Text("This removes your real bank data too, not only the sample. It cannot be undone. Your Enable Banking application stays in their control panel; delete it there too if you are done.")
            }
            .sheet(item: $csvURL) { url in
                ShareSheet(url: url)
            }
        }
    }

    private var bankSection: some View {
        Section {
            if let bank = model.settings.bankName, !model.isDemo {
                LabeledContent("Bank", value: bank)
                if let until = model.settings.consentValidUntil {
                    LabeledContent("Access valid until", value: until.formatted(date: .abbreviated, time: .omitted))
                }
                if model.settings.authorizedAccounts.count > 1 {
                    Picker("Account", selection: Binding(get: { model.settings.selectedAccountUID ?? "" }, set: { uid in Task { await model.switchAccount(to: uid) } })) {
                        ForEach(model.settings.authorizedAccounts) { account in
                            Text("\(account.title) \(account.subtitle)").tag(account.uid)
                        }
                    }
                }
                NavigationLink("Reconnect or change bank") { BankPickerView() }
                Button("Disconnect bank", role: .destructive) { Task { await model.disconnectBank() } }
            } else {
                NavigationLink("Connect your bank") { OnboardingView() }
            }
            NavigationLink("Keyword rules") { RulesView() }
        } header: {
            Text("Bank")
        } footer: {
            Text("Bank access lasts up to 180 days. You get a reminder two weeks and three days before it ends.")
        }
    }

    private var periodSection: some View {
        Section {
            Picker("Salary day", selection: Binding(get: { model.settings.startDay }, set: { day in model.updateSettings { $0.startDay = day } })) {
                ForEach(1...28, id: \.self) { Text($0 == 1 ? String(localized: "Calendar months") : "\($0)").tag($0) }
            }
            DatePicker("This period started on", selection: Binding(
                get: { model.period.start },
                set: { date in model.updateSettings { $0.periodOverrides[model.selectedPeriod] = Calendar.stockholm.startOfDay(for: date) } }
            ), displayedComponents: .date)
            if model.settings.periodOverrides[model.selectedPeriod] != nil {
                Button("Reset this period's start") { model.updateSettings { $0.periodOverrides[model.selectedPeriod] = nil } }
            }
        } header: {
            Text("Periods")
        } footer: {
            Text("A period runs from one salary to the next. When the salary day falls on a weekend or holiday, the period starts on the banking day before.")
        }
    }

    private var dataSection: some View {
        Section {
            Picker("Keep history", selection: Binding(get: { model.settings.retention.months }, set: { m in model.updateSettings { $0.retention = RetentionPolicy(months: m) } })) {
                ForEach(RetentionPolicy.options, id: \.months) { Text("\($0.months) months").tag($0.months) }
            }
            Button {
                do { csvURL = try model.exportCSV() } catch { model.errorMessage = error.localizedDescription }
            } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                .disabled(model.transactions.isEmpty)
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete everything", systemImage: "trash") }
        } header: {
            Text("Your data")
        } footer: {
            Text("Older transactions are removed automatically. Delete everything closes the bank connection and wipes the key, the settings and every transaction from this phone.")
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in AppModel.removeExports() }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
