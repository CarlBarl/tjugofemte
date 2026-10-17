import SwiftUI

/// What exists where. Written to be quotable on a website.
struct DataPageView: View {
    var body: some View {
        List {
            Section {
                Text("Tjugofemte is a budgeting app with no company behind the data. There is no server, no account, no analytics, no advertising kit. Your bank history is downloaded by your phone, from your bank, through a connection you own.")
            }
            Section("On this phone") {
                row("Transactions", "Date, amount, currency, counterparty text and category. Nothing else from the bank's response is kept. Stored in an encrypted SQLite database protected by iOS Data Protection, excluded from iCloud and computer backups, and trimmed to the history length you choose.")
                row("Your key", "An RSA key created inside this phone's Keychain. It signs every request to Enable Banking. It never existed as a file, is never backed up, and cannot move to another phone.")
                row("Session", "The Enable Banking session id and your Application ID, in the Keychain, device only.")
                row("Plan", "Budgets, income sources, keyword rules and settings, in the same local database.")
            }
            Section("Leaves this phone") {
                row("To api.enablebanking.com", "Signed requests for your bank list, your accounts and your transactions. Enable Banking is a licensed open banking provider in Finland and relays these to your bank. The requests carry your phone's IP address and the app name, which Enable Banking keeps in its logs for a time it does not publish.")
                row("To your bank and BankID", "When you connect, the system browser opens Enable Banking's login page, your bank's page and BankID. That is the same as logging in to your bank yourself.")
                row("Nowhere else", "The app contains no other network code. iOS App Privacy Report shows every domain it has contacted; try it.")
            }
            Section("Never") {
                row("No copies", "Nobody but you can read your transactions. Not the author of this app, not Apple, not Enable Banking beyond the relay.")
                row("No tracking", "No analytics, no crash reporting kit, no third-party code that phones home.")
                row("Delete everything", "One button closes the bank connection, deletes the key, the settings and every transaction, and overwrites the deleted database pages.")
            }
            Section("Honest limits") {
                Text("The private key is protected by the Keychain and your passcode, not by the Secure Enclave, because Enable Banking requires RSA. Enable Banking can see which accounts you access and when. The source code is public so all of this can be checked.")
            }
        }
        .appList()
        .navigationTitle("Your data")
    }

    private func row(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
