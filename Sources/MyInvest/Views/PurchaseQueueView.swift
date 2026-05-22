import SwiftUI

struct PurchaseQueueView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Binding var isAddingPlannedPurchase: Bool
    @State private var editingPurchase: PlannedPurchase?
    @State private var convertingPurchase: PlannedPurchase?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                projectionPanel
                upcomingPanel
                completedPanel
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(item: $editingPurchase) { purchase in
            PlannedPurchaseEditorView(editingPurchase: purchase)
                .environmentObject(store)
        }
        .sheet(item: $convertingPurchase) { purchase in
            TransactionEditorView(
                draftTransaction: InvestmentTransaction(
                    kind: .buy,
                    ticker: purchase.ticker,
                    companyName: purchase.companyName,
                    purchaseDate: Date(),
                    shares: 0,
                    purchasePrice: 0,
                    commission: 0,
                    cashAmount: nil,
                    notes: "План \(purchase.plannedAmount.formatted(AppFormatters.usd))" + (purchase.note.isEmpty ? "" : " • \(purchase.note)")
                ),
                onSave: { transaction in
                    store.markPlannedPurchaseCompletedAndAddTransaction(purchase, transaction: transaction)
                }
            )
            .environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Очередь к покупке")
                        .font(.largeTitle.weight(.semibold))
                    Text("План долгосрочного инвестора: дата, тикер и ориентировочная сумма покупки.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isAddingPlannedPurchase = true
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 300), spacing: 12)], spacing: 12) {
                MetricTile(
                    title: "Открытый план",
                    value: store.plannedPurchaseTotal.formatted(AppFormatters.usd),
                    detail: "\(store.openPlannedPurchases.count) покупок",
                    systemImage: "calendar.badge.plus",
                    tone: .accent
                )
                MetricTile(
                    title: "Следующая покупка",
                    value: store.nextPlannedPurchase?.ticker ?? "-",
                    detail: nextPurchaseDetail,
                    systemImage: "arrow.forward.circle"
                )
                MetricTile(
                    title: "Выполнено",
                    value: "\(store.completedPlannedPurchases.count)",
                    detail: "закрытых пунктов",
                    systemImage: "checkmark.circle",
                    tone: .positive
                )
            }
        }
    }

    private var upcomingPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("План покупок")
                        .font(.headline)
                    Spacer()
                    Text("\(store.openPlannedPurchases.count) открытых")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.openPlannedPurchases.isEmpty {
                    ContentUnavailableView("План пуст", systemImage: "calendar", description: Text("Добавьте следующую покупку, чтобы она не потерялась."))
                        .frame(height: 220)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.openPlannedPurchases) { purchase in
                            PlannedPurchaseRow(
                                purchase: purchase,
                                isCompleted: false,
                                onEdit: { editingPurchase = purchase },
                                onConvert: { convertingPurchase = purchase }
                            )
                            if purchase.id != store.openPlannedPurchases.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var projectionPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Проверка очереди покупок")
                    .font(.headline)

                let snapshots = store.projectedPlanSnapshots
                ForEach(Array(snapshots.enumerated()), id: \.offset) { _, snapshot in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 14) {
                            planSnapshotTitle(snapshot)
                            Spacer()
                            planSnapshotNumbers(snapshot)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            planSnapshotTitle(snapshot)
                            planSnapshotNumbers(snapshot)
                        }
                    }
                    .padding(.vertical, 6)

                    if snapshot.id != snapshots.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var completedPanel: some View {
        if !store.completedPlannedPurchases.isEmpty {
            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Выполненные")
                        .font(.headline)

                    VStack(spacing: 0) {
                        ForEach(store.completedPlannedPurchases) { purchase in
                            PlannedPurchaseRow(
                                purchase: purchase,
                                isCompleted: true,
                                onEdit: { editingPurchase = purchase },
                                onConvert: { convertingPurchase = purchase }
                            )
                            if purchase.id != store.completedPlannedPurchases.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var nextPurchaseDetail: String {
        guard let purchase = store.nextPlannedPurchase else { return "нет открытых пунктов" }
        return purchase.scheduledDate.formatted(AppFormatters.monthYear) + " • " + purchase.plannedAmount.formatted(AppFormatters.usd)
    }

    private func planSnapshotTitle(_ snapshot: ProjectedPlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(snapshot.horizonMonths) месяцев")
                .font(.headline)
            Text(snapshot.warnings.isEmpty ? "Открытые покупки учтены в прогнозе цели" : snapshot.warnings.joined(separator: " • "))
                .font(.caption)
                .foregroundStyle(snapshot.warnings.isEmpty ? Color.secondary : Color.orange)
                .lineLimit(2)
        }
    }

    private func planSnapshotNumbers(_ snapshot: ProjectedPlanSnapshot) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(snapshot.projectedInvestedAmount.formatted(AppFormatters.usd))
                    .font(.headline)
                    .monospacedDigit()
                Text("покупки")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(snapshot.projectedCashNeed.formatted(AppFormatters.usd))
                    .font(.headline)
                    .foregroundStyle(snapshot.projectedCashNeed > 0 ? .orange : .green)
                    .monospacedDigit()
                Text("нужно кэша")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlannedPurchaseRow: View {
    @EnvironmentObject private var store: PortfolioStore
    var purchase: PlannedPurchase
    var isCompleted: Bool
    var onEdit: () -> Void
    var onConvert: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullRow
            compactRow
        }
        .opacity(isCompleted ? 0.58 : 1)
        .padding(.vertical, 10)
    }

    private var fullRow: some View {
        HStack(spacing: 14) {
            Button {
                store.setPlannedPurchaseCompleted(purchase.id, isCompleted: !purchase.isCompleted)
            } label: {
                Image(systemName: purchase.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(purchase.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(purchase.isCompleted ? "Вернуть в очередь" : "Отметить выполненным")
            .accessibilityLabel(purchase.isCompleted ? "Вернуть \(purchase.ticker) в очередь" : "Отметить \(purchase.ticker) выполненным")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    CompanyLogoView(ticker: purchase.ticker, size: 24, cornerRadius: 7)
                    Text(purchase.ticker)
                        .font(.headline)
                    if !purchase.note.isEmpty {
                        Text(purchase.note)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.10), in: Capsule())
                    }
                }
                Text(purchase.companyName.isEmpty ? "Без названия" : purchase.companyName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(purchase.scheduledDate, format: AppFormatters.monthYear)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)

            Text(purchase.plannedAmount.formatted(AppFormatters.usd))
                .font(.headline)
                .monospacedDigit()
                .frame(width: 110, alignment: .trailing)

            Button {
                onConvert()
            } label: {
                Image(systemName: "arrow.right.doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .help("Создать сделку из плана")
            .disabled(purchase.isCompleted)

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Редактировать план")

            Button(role: .destructive) {
                store.deletePlannedPurchases(withIDs: [purchase.id])
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Удалить из плана")
            .accessibilityLabel("Удалить \(purchase.ticker) из плана")
        }
    }

    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    store.setPlannedPurchaseCompleted(purchase.id, isCompleted: !purchase.isCompleted)
                } label: {
                    Image(systemName: purchase.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(purchase.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(purchase.isCompleted ? "Вернуть \(purchase.ticker) в очередь" : "Отметить \(purchase.ticker) выполненным")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        CompanyLogoView(ticker: purchase.ticker, size: 22, cornerRadius: 7)
                        Text(purchase.ticker)
                            .font(.headline)
                    }
                    Text(purchase.companyName.isEmpty ? "Без названия" : purchase.companyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(purchase.plannedAmount.formatted(AppFormatters.usd))
                    .font(.headline)
                    .monospacedDigit()

                Button {
                    onConvert()
                } label: {
                    Image(systemName: "arrow.right.doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .disabled(purchase.isCompleted)
                .accessibilityLabel("Создать сделку из плана \(purchase.ticker)")

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Редактировать \(purchase.ticker)")

                Button(role: .destructive) {
                    store.deletePlannedPurchases(withIDs: [purchase.id])
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Удалить \(purchase.ticker) из плана")
            }

            HStack {
                Text(purchase.scheduledDate, format: AppFormatters.monthYear)
                if !purchase.note.isEmpty {
                    Text(purchase.note)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct PlannedPurchaseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PortfolioStore
    var editingPurchase: PlannedPurchase? = nil

    @State private var scheduledDate = Date()
    @State private var ticker = ""
    @State private var companyName = ""
    @State private var plannedAmount = ""
    @State private var note = ""
    @State private var companyNameWasEdited = false
    @State private var isApplyingCompanyName = false
    @State private var lastAppliedCompanyName = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("План") {
                    DatePicker("Дата", selection: $scheduledDate, displayedComponents: .date)
                    TextField("Тикер, например QQQ", text: $ticker)
                        .onChange(of: ticker) { _, newValue in
                            ticker = newValue.uppercased()
                        }
                    TextField("Название", text: $companyName)
                        .onChange(of: companyName) { _, _ in
                            if !isApplyingCompanyName {
                                companyNameWasEdited = true
                            }
                        }
                    TextField("Ориентировочная сумма", text: $plannedAmount)
                    TextField("Заметка, например Бонус", text: $note)
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

                Button(editingPurchase == nil ? "Добавить в очередь" : "Сохранить") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .accessibilityLabel("Добавить в очередь")
            }
            .padding(20)
        }
        .frame(width: 520)
        .frame(minHeight: 420)
        .onAppear(perform: hydrateFromEditingPurchase)
        .task(id: ticker.normalizedTicker) {
            await resolveCompanyName(for: ticker.normalizedTicker)
        }
    }

    private var canSave: Bool {
        !ticker.normalizedTicker.isEmpty && positive(plannedAmount) != nil
    }

    private func save() {
        guard let amount = positive(plannedAmount) else {
            errorMessage = "Сумма должна быть больше нуля."
            return
        }

        let purchase = PlannedPurchase(
            id: editingPurchase?.id ?? UUID(),
            scheduledDate: scheduledDate,
            ticker: ticker,
            companyName: companyName,
            plannedAmount: amount,
            note: note,
            isCompleted: editingPurchase?.isCompleted ?? false,
            createdAt: editingPurchase?.createdAt ?? Date()
        )
        if editingPurchase == nil {
            store.addPlannedPurchase(purchase)
        } else {
            store.updatePlannedPurchase(purchase)
        }
        dismiss()
    }

    private func hydrateFromEditingPurchase() {
        guard let editingPurchase else { return }
        scheduledDate = editingPurchase.scheduledDate
        ticker = editingPurchase.ticker
        companyName = editingPurchase.companyName
        plannedAmount = editingPurchase.plannedAmount.formatted(.number.precision(.fractionLength(0...2)))
        note = editingPurchase.note
    }

    private func resolveCompanyName(for symbol: String) async {
        guard !symbol.isEmpty else { return }

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

    private func positive(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let result = Double(normalized), result > 0 else { return nil }
        return result
    }
}
