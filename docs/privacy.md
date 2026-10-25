# Tjugofemte privacy policy

Tjugofemte is a budgeting app for iPhone. It has no server, no user accounts and no analytics. The author never receives any data from the app.

**What the app stores, on your phone only:** the transactions you fetch (date, amount, currency, counterparty text, category), your budgets, income sources and keyword rules, your savings goal with the wants you hearted and which categories count as needs, an RSA key generated on the phone, and the Enable Banking session id and Application ID. Transactions are kept only as long as you choose (the setup asks whether to keep up to 12 months or 3, and Settings offers 3, 12 or 24); anything older is deleted. The database is protected by iOS Data Protection and excluded from iCloud and computer backups. Keychain items are device-only and never synced.

**What the app works out:** your savings rate, what you usually spend and your recurring charges are calculated on the phone from the stored transactions. They are not stored separately and never leave the phone.

**What leaves your phone:** signed requests to Enable Banking (`api.enablebanking.com`), a licensed account information service provider in Finland, which relays them to your bank. These requests include your phone's IP address and the app's name. When you connect a bank, the system browser opens Enable Banking's login page, your bank and BankID, exactly as if you logged in yourself. Nothing is sent anywhere else.

**Your Enable Banking application** is registered by you, in your own name, under Enable Banking's terms. The author of Tjugofemte is not a party to that relationship and cannot access it.

**Deleting your data:** "Delete everything" in Settings closes the Enable Banking session, deletes the key and every transaction, and overwrites the deleted database pages. To remove the registration itself, delete the application in Enable Banking's control panel.

**Changes:** this page is versioned in the public repository together with the source code.

Contact: open an issue in the repository.
