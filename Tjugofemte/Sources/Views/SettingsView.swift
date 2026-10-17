import SwiftUI
import BudgetCore
import LocalStore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            Screen(banner: true) {
                ScreenTitle(label: "Tjugofemte", title: String(localized: "Settings"))
                SectionLabel(text: "Bank")
                bankCard
                SectionLabel(text: "Periods").padding(.top, 8)
                periodCard
                SectionLabel(text: "Your data").padding(.top, 8)
                dataCard
                SectionLabel(text: "About").padding(.top, 8)
                aboutCard
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Delete everything?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { Task { await model.deleteEverything() } }
            } message: {
                Text("This removes your real bank data too, not only the sample. It cannot be undone. Your Enable Banking application stays in their control panel; delete it there too if you are done.")
            }
            .sheet(item: $csvURL) { url in ShareSheet(url: url) }
        }
    }

    private var bankCard: some View {
        RowCard {
            if let bank = model.settings.bankName, !model.isDemo {
                Row(title: String(localized: "Bank"), caption: model.settings.consentValidUntil.map {
                    String(localized: "Access valid until \($0.formatted(date: .abbreviated, time: .omitted)). You get a reminder two weeks and three days before.")
                }) {
                    Text(bank).appFont(size: 15, weight: .medium).foregroundStyle(Tokens.muted)
                }
                Hairline()
                if model.settings.authorizedAccounts.count > 1 {
                    Row(title: String(localized: "Account"), caption: String(localized: "Switching keeps the plan and refetches history for the chosen account.")) {
                        Picker("Account", selection: Binding(get: { model.settings.selectedAccountUID ?? "" }, set: { uid in Task { await model.switchAccount(to: uid) } })) {
                            ForEach(model.settings.authorizedAccounts) { account in
                                Text("\(account.title) \(account.subtitle)").tag(account.uid)
                            }
                        }
                        .pickerStyle(.menu).tint(Tokens.accent)
                    }
                    Hairline()
                }
                LinkRow(title: String(localized: "Reconnect or change bank")) { BankPickerView() }
                Hairline()
                LinkRow(title: String(localized: "Keyword rules"), caption: String(localized: "Which words put a transaction in which category.")) { RulesView() }
                Hairline()
                Button { Task { await model.disconnectBank() } } label: {
                    Row(title: String(localized: "Disconnect bank")) { EmptyView() }.foregroundStyle(Tokens.over).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                LinkRow(title: String(localized: "Connect your bank"), caption: String(localized: "About ten minutes the first time.")) { OnboardingView() }
                Hairline()
                LinkRow(title: String(localized: "Keyword rules")) { RulesView() }
            }
        }
    }

    private var periodCard: some View {
        RowCard {
            Row(title: String(localized: "Payday"), caption: String(localized: "When it falls on a weekend or holiday, the period starts on the banking day before.")) {
                Picker("Payday", selection: Binding(get: { model.settings.startDay }, set: { day in model.updateSettings { $0.startDay = day } })) {
                    ForEach(1...28, id: \.self) { Text(PeriodText.ordinalDay($0)).tag($0) }
                }
                .pickerStyle(.menu).tint(Tokens.accent)
            }
            Hairline()
            Row(title: String(localized: "This period started"), caption: PeriodText.title(model.selectedPeriod)) {
                DatePicker("", selection: Binding(
                    get: { model.period.start },
                    set: { date in model.updateSettings { $0.periodOverrides[model.selectedPeriod] = Calendar.stockholm.startOfDay(for: date) } }
                ), displayedComponents: .date)
                .labelsHidden().tint(Tokens.accent)
            }
            if model.settings.periodOverrides[model.selectedPeriod] != nil {
                Hairline()
                TextAction(title: "Reset this period's start") { model.updateSettings { $0.periodOverrides[model.selectedPeriod] = nil } }
            }
        }
    }

    private var dataCard: some View {
        RowCard {
            Row(title: String(localized: "Keep history"), caption: String(localized: "Older transactions are removed automatically.")) {
                Picker("Keep history", selection: Binding(get: { model.settings.retention.months }, set: { m in model.updateSettings { $0.retention = RetentionPolicy(months: m) } })) {
                    ForEach(RetentionPolicy.options, id: \.months) { Text("\($0.months) months").tag($0.months) }
                }
                .pickerStyle(.menu).tint(Tokens.accent)
            }
            Hairline()
            Row(title: String(localized: "Sample data"), caption: String(localized: "Three periods of made-up Swedish transactions. Your real data is untouched.")) {
                Toggle("", isOn: Binding(get: { model.isDemo }, set: { $0 ? model.startDemo() : model.stopDemo() })).labelsHidden().tint(Tokens.accent)
            }
            Hairline()
            Button {
                do { csvURL = try model.exportCSV() } catch { model.errorMessage = error.localizedDescription }
            } label: {
                Row(title: String(localized: "Export CSV"), caption: String(localized: "Every transaction on this phone, for a spreadsheet.")) {
                    Image(systemName: "square.and.arrow.up").appFont(size: 16, weight: .semibold).foregroundStyle(model.transactions.isEmpty ? Tokens.dim : Tokens.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.transactions.isEmpty)
            Hairline()
            Button { confirmDelete = true } label: {
                Row(title: String(localized: "Delete everything"), caption: String(localized: "Closes the bank connection and wipes the key, the plan and every transaction from this phone.")) {
                    Image(systemName: "trash").appFont(size: 16, weight: .semibold)
                }
                .foregroundStyle(Tokens.over)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutCard: some View {
        RowCard {
            LinkRow(title: String(localized: "Your data, explained")) { DataPageView() }
            Hairline()
            Link(destination: Links.repository) { Row(title: String(localized: "Source code")) { Image(systemName: "arrow.up.right").appFont(size: 14, weight: .semibold).foregroundStyle(Tokens.dim) } }
            Hairline()
            Link(destination: Links.privacy) { Row(title: String(localized: "Privacy policy")) { Image(systemName: "arrow.up.right").appFont(size: 14, weight: .semibold).foregroundStyle(Tokens.dim) } }
            Hairline()
            Row(title: String(localized: "Version")) {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev").appFont(size: 15).foregroundStyle(Tokens.muted)
            }
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
