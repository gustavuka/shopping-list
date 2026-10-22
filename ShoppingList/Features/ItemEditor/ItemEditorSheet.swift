import SwiftUI

/// Edit name, quantity, note and section. Changes apply on "Save" only.
struct ItemEditorSheet: View {
    let item: ItemRecord

    @Environment(ListStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantity: String
    @State private var note: String
    @State private var category: Category

    init(item: ItemRecord) {
        self.item = item
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantity ?? "")
        _note = State(initialValue: item.note ?? "")
        _category = State(initialValue: item.category)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .font(.title3.weight(.medium))
                    TextField("Quantity (e.g. 2, 500 g)", text: $quantity)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Section") {
                    Picker("Section", selection: $category) {
                        ForEach(Category.allCases) { category in
                            Label {
                                Text(category.displayName)
                            } icon: {
                                CategoryBadge(category: category, size: 28)
                            }
                            .tag(category)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        store.update(item, name: name, quantity: quantity, note: note, category: category)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
