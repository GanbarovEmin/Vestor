import SwiftUI

struct PurchaseQueueView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Binding var isAddingPlannedPurchase: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                upcomingPanel
                completedPanel
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
                    Text("Первые 12 месяцев без изменений")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.openPlannedPurchases.isEmpty {
                    ContentUnavailableView("План пуст", systemImage: "calendar", description: Text("Добавьте следующую покупку, чтобы она не потерялась."))
                        .frame(height: 220)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.openPlannedPurchases) { purchase in
                            PlannedPurchaseRow(purchase: purchase, isCompleted: false)
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
    private var completedPanel: some View {
        if !store.completedPlannedPurchases.isEmpty {
            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Выполненные")
                        .font(.headline)

                    VStack(spacing: 0) {
                        ForEach(store.completedPlannedPurchases) { purchase in
                            PlannedPurchaseRow(purchase: purchase, isCompleted: true)
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
}

private struct PlannedPurchaseRow: View {
    @EnvironmentObject private var store: PortfolioStore
    var purchase: PlannedPurchase
    var isCompleted: Bool

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
                    Text(purchase.ticker)
                        .font(.headline)
                    Text(purchase.companyName.isEmpty ? "Без названия" : purchase.companyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(purchase.plannedAmount.formatted(AppFormatters.usd))
                    .font(.headline)
                    .monospacedDigit()

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

    @State private var scheduledDate = Date()
    @State private var ticker = ""
    @State private var companyName = ""
    @State private var plannedAmount = ""
    @State private var note = ""
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

                Button("Добавить в очередь") {
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
    }

    private var canSave: Bool {
        !ticker.normalizedTicker.isEmpty && positive(plannedAmount) != nil
    }

    private func save() {
        guard let amount = positive(plannedAmount) else {
            errorMessage = "Сумма должна быть больше нуля."
            return
        }

        store.addPlannedPurchase(PlannedPurchase(
            scheduledDate: scheduledDate,
            ticker: ticker,
            companyName: companyName,
            plannedAmount: amount,
            note: note
        ))
        dismiss()
    }

    private func positive(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let result = Double(normalized), result > 0 else { return nil }
        return result
    }
}
