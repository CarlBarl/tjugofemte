import SwiftUI
import EnableBankingKit

struct BankPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var askingSSN: Bank?
    @State private var ssn = ""
    @State private var query = ""

    private var shownBanks: [Bank] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? model.banks : model.banks.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            if model.banks.isEmpty && !model.isBusy {
                Text("No banks loaded yet. Pull to retry.").foregroundStyle(.secondary)
            }
            ForEach(shownBanks, id: \.name) { bank in
                Button { start(bank) } label: {
                    HStack {
                        Text(bank.name)
                        if bank.beta == true { Text("beta").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .tint(.primary)
            }
        }
        .appList()
        .navigationTitle("Choose bank")
        .searchable(text: $query, prompt: "Search bank")
        .overlay { if model.isBusy { ProgressView() } }
        .task { if model.banks.isEmpty { await model.loadBanks() } }
        .refreshable { await model.loadBanks() }
        .navigationDestination(isPresented: Binding(get: { model.stage == .needsAccount }, set: { _ in })) { AccountPickerView() }
        .onChange(of: model.stage) { _, stage in if stage == .ready { dismiss() } }
        .alert("Personal identity number", isPresented: Binding(get: { askingSSN != nil }, set: { if !$0 { askingSSN = nil } })) {
            TextField("YYYYMMDDXXXX", text: $ssn).keyboardType(.numberPad)
            Button("Continue") {
                guard let bank = askingSSN else { return }
                Task { await model.connect(bank: bank, psuID: ssn) }
                askingSSN = nil
            }
            Button("Cancel", role: .cancel) { askingSSN = nil }
        } message: {
            Text("This bank needs it to start BankID. It is sent once and never stored.")
        }
    }

    private func start(_ bank: Bank) {
        if model.requiredCredentials(for: bank).contains(where: { ["ssn", "personnummer", "psu_id", "userid"].contains($0.lowercased()) }) {
            askingSSN = bank
        } else {
            Task { await model.connect(bank: bank, psuID: nil) }
        }
    }
}

struct AccountPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(model.settings.authorizedAccounts) { account in
                    Button {
                        Task { await model.chooseAccount(account.uid) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.title)
                                Text(account.subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer()
                            if account.uid == model.settings.selectedAccountUID { Image(systemName: "checkmark") }
                        }
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("Pick the account your salary lands on. Transfers to your other linked accounts are recognized automatically. You can switch later under Settings without a new BankID login.")
            }
        }
        .appList()
        .navigationTitle("Which account?")
        .overlay { if model.isBusy && model.settings.authorizedAccounts.isEmpty { ProgressView() } }
        .task { await model.ensureAccountsListed() }
    }
}
