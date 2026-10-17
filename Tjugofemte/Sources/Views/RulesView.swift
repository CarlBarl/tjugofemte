import SwiftUI
import BudgetCore

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var keyword = ""
    @State private var categoryID = DefaultCategory.groceries.rawValue

    var body: some View {
        List {
            Section {
                TextField("Keyword, for example ica", text: $keyword).textInputAutocapitalization(.never)
                Picker("Category", selection: $categoryID) {
                    ForEach(CategoryInfo.all, id: \.self) { Text(CategoryInfo.name($0)).tag($0) }
                }
                Button("Add rule") {
                    model.addRule(KeywordRule(keyword: keyword.trimmingCharacters(in: .whitespaces), categoryID: categoryID))
                    keyword = ""
                }
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("New rule")
            } footer: {
                Text("Keywords match whole words, ignoring case. Your rules win over the built-in ones, newest first.")
            }
            Section("Your rules") {
                if model.rules.isEmpty { Text("None yet. Categorize a transaction and switch on “Always” to create one.").foregroundStyle(.secondary) }
                ForEach(Array(model.rules.enumerated()), id: \.offset) { _, rule in
                    HStack {
                        Text(rule.keyword)
                        Spacer()
                        Text(CategoryInfo.name(rule.categoryID)).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in offsets.map { model.rules[$0] }.forEach(model.deleteRule) }
            }
        }
        .navigationTitle("Keyword rules")
    }
}
