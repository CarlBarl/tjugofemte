import SwiftUI
import EnableBankingKit

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var applicationID = ""
    @State private var copied: String?

    var body: some View {
        List {
            Section {
                Text("Tjugofemte never sees your bank data. You create your own free connection at Enable Banking, and this phone talks to the bank directly. The steps below take about ten minutes.")
            }

            Section("1. Create your key") {
                if model.hasKey, let pem = model.publicKeyPEM() {
                    Text(pem).font(.system(.caption2, design: .monospaced)).lineLimit(6).textSelection(.enabled)
                    copyButton("Copy public key", pem)
                    Text("The private half was created inside this phone and cannot be exported.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await model.generateKey() }
                    } label: {
                        if model.isBusy { ProgressView() } else { Label("Generate key", systemImage: "key") }
                    }
                    .disabled(model.isBusy)
                }
            }

            Section("2. Register an application at Enable Banking") {
                Link(destination: Links.controlPanel) { Label("Open the Enable Banking control panel", systemImage: "safari") }
                step("Sign in with your email, then add a new application in the Production environment, not Sandbox.")
                step("Name it anything, for example Tjugofemte.")
                step("Redirect URL: paste the address below. It is a page in this app's open source repository that only hands the login back to the app.")
                copyButton("Copy redirect URL", AuthCoordinator.redirectURL.absoluteString)
                step("Choose to provide your own public key and paste the key from step 1.")
                step("Privacy policy and terms URLs: paste these two.")
                copyButton("Copy privacy URL", Links.privacy.absoluteString)
                copyButton("Copy terms URL", Links.terms.absoluteString)
            }

            Section("3. Paste the Application ID") {
                if let id = model.applicationID {
                    Text(id).font(.system(.footnote, design: .monospaced))
                    Button("Change", role: .destructive) { model.saveApplicationID(""); applicationID = "" }.disabled(true)
                } else {
                    TextField("Application ID", text: $applicationID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save") { model.saveApplicationID(applicationID) }.disabled(applicationID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("4. Activate by linking your accounts") {
                step("In the control panel, open your application and choose Activate by linking accounts.")
                step("Link every account you want to see here. Accounts you skip stay invisible to the app.")
                step("The application will show as Restricted and Active. That is the free personal mode.")
            }

            Section("5. Connect your bank") {
                NavigationLink { BankPickerView() } label: { Label("Choose bank", systemImage: "building.columns") }
                    .disabled(model.stage == .needsKey || model.stage == .needsApplicationID)
            }
        }
        .navigationTitle("Connect your bank")
        .onAppear { applicationID = model.applicationID ?? "" }
    }

    private func step(_ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary) }
    }

    private func copyButton(_ title: LocalizedStringKey, _ value: String) -> some View {
        Button {
            model.copyLocally(value)
            copied = value
        } label: {
            Label(copied == value ? "Copied" : title, systemImage: copied == value ? "checkmark" : "doc.on.doc")
        }
    }
}

struct BankPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var askingSSN: Bank?
    @State private var ssn = ""

    var body: some View {
        List {
            if model.banks.isEmpty && !model.isBusy {
                Text("No banks loaded yet. Pull to retry.").foregroundStyle(.secondary)
            }
            ForEach(model.banks, id: \.name) { bank in
                Button { start(bank) } label: {
                    HStack {
                        Text(bank.name)
                        if bank.beta == true { Text("beta").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .tint(.primary)
            }
        }
        .navigationTitle("Choose bank")
        .overlay { if model.isBusy { ProgressView() } }
        .task { if model.banks.isEmpty { await model.loadBanks() } }
        .refreshable { await model.loadBanks() }
        .navigationDestination(isPresented: Binding(get: { !model.pendingAccounts.isEmpty }, set: { _ in })) { AccountPickerView() }
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
                ForEach(model.pendingAccounts, id: \.uid) { account in
                    Button {
                        Task { await model.chooseAccount(account.uid) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(account.name ?? account.product ?? account.uid)
                            if let product = account.product, product != account.name { Text(product).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            } footer: {
                Text("Pick the account your salary lands on. Transfers to your other linked accounts are recognized automatically.")
            }
        }
        .navigationTitle("Which account?")
    }
}
