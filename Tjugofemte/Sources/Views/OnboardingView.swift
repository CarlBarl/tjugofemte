import SwiftUI
import EnableBankingKit

/// Five screens, one action each. Step 2 mirrors the Enable Banking registration form field by field,
/// in the form's own order, so the user never has to scroll back and forth between app and browser.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var choosingBank = false

    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                KeyStep().tag(0)
                RegisterStep().tag(1)
                ApplicationIDStep().tag(2)
                LinkAccountsStep().tag(3)
                ConnectStep().tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            VStack(spacing: 6) {
                HStack {
                    Group { if step > 0 { TextAction(title: "Back") { withAnimation(.snappy) { step -= 1 } } } }
                        .frame(width: 110, alignment: .leading)
                    Spacer()
                    StepDots(count: stepCount, current: step)
                    Spacer()
                    Text("Step \(step + 1) of \(stepCount)").appFont(size: 13).foregroundStyle(Tokens.dim)
                        .frame(width: 110, alignment: .trailing)
                }
                if step < stepCount - 1 {
                    BigButton(title: "Next", isEnabled: canAdvance) { withAnimation(.snappy) { step += 1 } }
                } else {
                    BigButton(title: "Choose bank", isEnabled: model.stage != .needsKey && model.stage != .needsApplicationID) { choosingBank = true }
                }
            }
            .padding(.horizontal, Tokens.screenPadding)
            .padding(.vertical, 12)
            .background(Tokens.bg)
        }
        .background(Tokens.bg)
        .navigationTitle("Connect your bank")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $choosingBank) { BankPickerView() }
        .onAppear { step = firstOpenStep }
    }

    private var canAdvance: Bool {
        switch step {
        case 0: model.hasKey
        case 2: model.applicationID != nil
        default: true
        }
    }

    private var firstOpenStep: Int {
        if !model.hasKey { return 0 }
        if model.applicationID == nil { return 1 }
        if model.sessionID == nil { return 3 }
        return 4
    }
}

/// The step's title and one paragraph, above the list rather than inside it.
private struct StepIntro: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).appFont(size: 28, weight: .bold, rounded: true).foregroundStyle(Tokens.text)
            Text(text).appFont(size: 15).foregroundStyle(Tokens.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.screenPadding)
        .padding(.top, 8)
    }
}

/// A form field as the control panel shows it, with the value to paste and a copy button.
private struct CopyRow: View {
    @Environment(AppModel.self) private var model
    let label: LocalizedStringKey
    let value: String
    var monospaced = false
    @State private var copied = false

    var body: some View {
        Button {
            model.copyLocally(value)
            copied = true
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.subheadline).foregroundStyle(.secondary)
                    Text(value).font(monospaced ? .system(.footnote, design: .monospaced) : .body).lineLimit(2).foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.green : Color.accentColor)
            }
        }
        .tint(.primary)
    }
}

private struct InfoRow: View {
    let label: LocalizedStringKey
    let value: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

private struct KeyStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            StepIntro(title: "Your key", text: "Tjugofemte never sees your bank data. Your phone creates a key, you register it at Enable Banking yourself, and the phone talks to the bank directly. About ten minutes, once.")
            List {
            Section {
                if model.hasKey, let pem = model.publicKeyPEM() {
                    Label("Key created inside this phone", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Text(pem).font(.system(.caption2, design: .monospaced)).lineLimit(4).foregroundStyle(.secondary)
                    ShareLink(item: pem) { Label("Share public key to a computer", systemImage: "square.and.arrow.up") }
                } else {
                    Button {
                        Task { await model.generateKey() }
                    } label: {
                        HStack {
                            Label("Create key", systemImage: "key")
                            if model.isBusy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(model.isBusy)
                }
            } footer: {
                Text("The private half never leaves the phone and cannot be exported. The public half is what you hand to Enable Banking in the next step. Sharing it is safe.")
            }
            }
            .appList()
        }
        .background(Tokens.bg)
    }
}

private struct RegisterStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            StepIntro(title: "Register the app at Enable Banking", text: "Open the control panel, sign in with your email, and fill the form below in this order. Every value is one tap to copy.")
            List {
            Section {
                Link(destination: Links.controlPanel) { Label("Open the Enable Banking control panel", systemImage: "safari") }
                Text("If you prefer a computer: share the public key to it from the previous step, do this step there, and come back here for step 3.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("The form, top to bottom") {
                InfoRow(label: "1. Environment", value: "Production")
                InfoRow(label: "2. Key", value: "Choose “Generate outside the browser and import public certificate”")
                CopyRow(label: "3. Application name", value: "Tjugofemte")
                CopyRow(label: "Description", value: String(localized: "Private budgeting app"))
                InfoRow(label: "Data protection email", value: "Your own email address")
                CopyRow(label: "Privacy policy URL", value: Links.privacy.absoluteString)
                CopyRow(label: "Terms of service URL", value: Links.terms.absoluteString)
                CopyRow(label: "4. Redirect URL", value: AuthCoordinator.redirectURL.absoluteString)
                if let pem = model.publicKeyPEM() {
                    CopyRow(label: "5. Public certificate", value: pem, monospaced: true)
                }
                InfoRow(label: "Then", value: "Tap Register")
            }
            }
            .appList()
        }
        .background(Tokens.bg)
    }
}

private struct ApplicationIDStep: View {
    @Environment(AppModel.self) private var model
    @State private var typed = ""

    var body: some View {
        VStack(spacing: 0) {
            StepIntro(title: "Application ID", text: "After Register, the control panel shows your application with its ID in the heading, next to the name. Copy it and paste it here.")
            List {
            Section {
                if let id = model.applicationID {
                    Label(id, systemImage: "checkmark.seal.fill").font(.system(.footnote, design: .monospaced)).foregroundStyle(.green)
                    Button("Use another Application ID", role: .destructive) { model.clearApplicationID() }
                } else {
                    HStack {
                        TextField("Application ID", text: $typed).textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(.body, design: .monospaced))
                        Button("Paste") { if let s = model.pasteboardString() { typed = s } }.buttonStyle(.bordered)
                    }
                    Button("Save") { model.saveApplicationID(typed) }
                        .disabled(typed.trimmingCharacters(in: .whitespaces).count < 8)
                }
            } footer: {
                Text("Looks like 7577f15e-45a9-43cd-a1b3-4f5b1d3387f2. It is not secret, but it is yours.")
            }
            }
            .appList()
        }
        .background(Tokens.bg)
    }
}

private struct LinkAccountsStep: View {
    var body: some View {
        VStack(spacing: 0) {
            StepIntro(title: "Link your accounts", text: "This is what makes the free personal mode work: Enable Banking only ever returns the accounts you link here.")
            List {
            Section {
                InfoRow(label: "1", value: "On your application's page in the control panel, tap “Activate by linking accounts”.")
                InfoRow(label: "2", value: "Choose Sweden, your bank, and personal. Tap Link.")
                InfoRow(label: "3", value: "Log in with BankID and approve every account you want to see. Skipped accounts stay invisible to the app.")
                InfoRow(label: "4", value: "The application should now say Active and Restricted. That is correct.")
            }
            Section {
                Label {
                    Text("With Swedbank and the savings banks, this bank login sometimes never loads on a phone. If it spins for more than 20 seconds, finish this one step on a computer at enablebanking.com/cp. Everything else stays on the phone.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                .font(.footnote)
            }
            }
            .appList()
        }
        .background(Tokens.bg)
    }
}

private struct ConnectStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            StepIntro(title: "Connect", text: "Last step. Choose your bank, log in with BankID, and pick the account your salary lands on.")
            List {
            Section {
                Label("Bank access lasts up to 180 days. The app reminds you before it ends.", systemImage: "clock")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            }
            .appList()
        }
        .background(Tokens.bg)
    }
}
