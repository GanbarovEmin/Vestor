import SwiftUI

struct ImportWizardView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State var draft: CSVImportDraft
    var onClose: () -> Void
    @State private var presetName = "Последний импорт"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Мастер импорта")
                    .font(.title2.weight(.semibold))
                Text("\(draft.rows.count) строк из \(draft.sourceURL.lastPathComponent)")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            Form {
                Section("Mapping колонок") {
                    mappingPicker("Дата", keyPath: \.date)
                    mappingPicker("Тип", keyPath: \.type)
                    mappingPicker("Тикер", keyPath: \.ticker)
                    mappingPicker("Название", keyPath: \.name)
                    mappingPicker("Количество", keyPath: \.shares)
                    mappingPicker("Цена", keyPath: \.price)
                    mappingPicker("Комиссия", keyPath: \.commission)
                    mappingPicker("Сумма", keyPath: \.cashAmount)
                    mappingPicker("Заметки", keyPath: \.notes)
                    TextField("Название preset", text: $presetName)
                    Button("Применить mapping") {
                        reloadDraft(savePreset: true)
                    }
                }

                Section("Предпросмотр") {
                    ForEach($draft.rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $row.isIncluded) {
                                HStack {
                                    Text("#\(row.sourceRowIndex)")
                                        .foregroundStyle(.secondary)
                                    TextField("Тикер", text: $row.ticker)
                                        .frame(width: 80)
                                    Text(row.kind?.title ?? "Тип?")
                                    Spacer()
                                    Text(row.transaction?.displayAmount.formatted(AppFormatters.usd) ?? "-")
                                        .monospacedDigit()
                                }
                            }
                            HStack {
                                TextField("Количество", value: $row.shares, format: .number)
                                TextField("Цена", value: $row.price, format: .number)
                                TextField("Сумма", value: $row.cashAmount, format: .number)
                            }
                            if !row.validationIssues.isEmpty {
                                Text(row.validationIssues.map(\.rawValue).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Отмена", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(draft.validTransactions.count) готово к импорту")
                    .foregroundStyle(.secondary)
                Button("Импортировать") {
                    store.importDraft(draft)
                    Task { await store.refreshAll() }
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validTransactions.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 860, height: 720)
    }

    private func mappingPicker(_ title: String, keyPath: WritableKeyPath<ImportColumnMapping, String?>) -> some View {
        Picker(title, selection: Binding(
            get: { draft.mapping[keyPath: keyPath] ?? "" },
            set: { draft.mapping[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )) {
            Text("-").tag("")
            ForEach(draft.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }

    private func reloadDraft(savePreset: Bool) {
        if let next = try? store.previewImportDraft(
            from: draft.sourceURL,
            mapping: draft.mapping,
            presetName: savePreset ? presetName : nil
        ) {
            draft = next
        }
    }
}
