import SwiftUI

struct TransactionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PortfolioStore
    var editingTransaction: InvestmentTransaction? = nil
    var draftTransaction: InvestmentTransaction? = nil
    var onSave: ((InvestmentTransaction) -> Void)? = nil

    @State private var kind: TransactionKind = .buy
    @State private var ticker = ""
    @State private var companyName = ""
    @State private var purchaseDate = Date()
    @State private var shares = ""
    @State private var price = ""
    @State private var commission = "0"
    @State private var cashAmount = ""
    @State private var notes = ""
    @State private var companyNameWasEdited = false
    @State private var isApplyingCompanyName = false
    @State private var lastAppliedCompanyName = ""
    @State private var isFetchingPrice = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Тип") {
                    Picker("Операция", selection: $kind) {
                        ForEach(TransactionKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage)
                                .tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Акция") {
                    TextField("Тикер, например AAPL", text: $ticker)
                        .onChange(of: ticker) { _, newValue in
                            ticker = newValue.uppercased()
                        }
                    TextField("Название компании", text: $companyName)
                        .onChange(of: companyName) { _, _ in
                            if !isApplyingCompanyName {
                                companyNameWasEdited = true
                            }
                        }
                }
                .disabled(!kind.affectsPosition && kind != .dividend)

                Section(kind.affectsPosition ? "Сделка" : "Деньги") {
                    DatePicker("Дата", selection: $purchaseDate, displayedComponents: .date)
                    if kind.affectsPosition {
                        TextField("Количество", text: $shares)
                        HStack {
                            TextField("Цена", text: $price)
                            Button {
                                fetchPrice()
                            } label: {
                                if isFetchingPrice {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Получить цену", systemImage: "arrow.down.circle")
                                }
                            }
                            .disabled(ticker.normalizedTicker.isEmpty || isFetchingPrice)
                        }
                        TextField("Комиссия", text: $commission)
                    } else {
                        TextField("Сумма", text: $cashAmount)
                    }
                    TextField("Заметки", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .padding(20)

            Divider()

            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Отмена")

                Spacer()

                Button(editingTransaction == nil ? "Добавить сделку" : "Сохранить") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .accessibilityLabel(editingTransaction == nil ? "Добавить сделку" : "Сохранить сделку")
            }
            .padding(20)
        }
        .frame(width: 520)
        .frame(minHeight: 520)
        .onAppear(perform: hydrateFromInitialTransaction)
        .task(id: ticker.normalizedTicker) {
            await resolveCompanyName(for: ticker.normalizedTicker)
        }
    }

    private var canSave: Bool {
        if kind.affectsPosition {
            return !ticker.normalizedTicker.isEmpty &&
            positive(shares) != nil &&
            positive(price) != nil &&
            parsed(commission) != nil
        }
        return positive(cashAmount) != nil
    }

    private func fetchPrice() {
        errorMessage = nil
        isFetchingPrice = true

        Task {
            do {
                let fetchedPrice = try await store.fetchClose(for: ticker, on: purchaseDate)
                price = fetchedPrice.formatted(.number.precision(.fractionLength(2...4)))
            } catch {
                errorMessage = error.localizedDescription
            }
            isFetchingPrice = false
        }
    }

    private func resolveCompanyName(for symbol: String) async {
        guard !symbol.isEmpty, kind.affectsPosition || kind == .dividend else { return }

        if let localName = store.bestCompanyName(for: symbol) {
            applyCompanyName(localName)
            return
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }

        if let profile = await store.resolveCompanyProfile(for: symbol) {
            applyCompanyName(profile.companyName)
        }
    }

    private func applyCompanyName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !companyNameWasEdited || companyName.isEmpty || companyName == lastAppliedCompanyName else { return }

        isApplyingCompanyName = true
        companyName = trimmed
        lastAppliedCompanyName = trimmed
        companyNameWasEdited = false
        isApplyingCompanyName = false
    }

    private func save() {
        let sharesValue = parsed(shares) ?? 0
        let priceValue = parsed(price) ?? 0
        let commissionValue = parsed(commission) ?? 0
        let cashValue = parsed(cashAmount)

        if kind.affectsPosition, sharesValue <= 0 || priceValue <= 0 {
            errorMessage = "Количество и цена должны быть больше нуля."
            return
        }

        guard kind.affectsPosition || (cashValue ?? 0) > 0 else {
            errorMessage = "Проверьте сумму."
            return
        }

        let transaction = InvestmentTransaction(
            id: editingTransaction?.id ?? UUID(),
            kind: kind,
            ticker: ticker,
            companyName: companyName,
            purchaseDate: purchaseDate,
            shares: sharesValue,
            purchasePrice: priceValue,
            commission: commissionValue,
            cashAmount: cashValue,
            notes: notes
        )

        if let onSave {
            onSave(transaction)
        } else if editingTransaction == nil {
            store.add(transaction)
        } else {
            store.update(transaction)
        }
        Task {
            await store.refreshAll()
        }
        dismiss()
    }

    private func hydrateFromInitialTransaction() {
        guard let transaction = editingTransaction ?? draftTransaction else { return }
        kind = transaction.kind
        ticker = transaction.ticker
        companyName = transaction.companyName
        purchaseDate = transaction.purchaseDate
        shares = transaction.shares == 0 ? "" : transaction.shares.formatted(.number.precision(.fractionLength(0...9)))
        price = transaction.purchasePrice == 0 ? "" : transaction.purchasePrice.formatted(.number.precision(.fractionLength(0...6)))
        commission = transaction.commission.formatted(.number.precision(.fractionLength(0...2)))
        cashAmount = transaction.cashAmount?.formatted(.number.precision(.fractionLength(0...2))) ?? ""
        notes = transaction.notes
    }

    private func parsed(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let result = Double(normalized), result >= 0 else { return nil }
        return result
    }

    private func positive(_ value: String) -> Double? {
        guard let result = parsed(value), result > 0 else { return nil }
        return result
    }
}
