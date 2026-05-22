import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TransactionsView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Binding var isAddingTransaction: Bool
    @State private var editingTransaction: InvestmentTransaction?
    @State private var exportedURL: URL?
    @State private var importDraft: CSVImportDraft?

    var body: some View {
        VStack(spacing: 0) {
            transactionHeader
                .padding(22)

            Divider()

            if store.transactions.isEmpty {
                EmptyPortfolioView(isAddingTransaction: $isAddingTransaction)
            } else {
                List {
                    ForEach(store.transactionsNewestFirst) { transaction in
                        TransactionRow(transaction: transaction)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingTransaction = transaction
                            }
                            .contextMenu {
                                Button {
                                    editingTransaction = transaction
                                } label: {
                                    Label("Редактировать", systemImage: "pencil")
                                }
                            }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditorView(editingTransaction: transaction)
                .environmentObject(store)
        }
        .sheet(item: $importDraft) { draft in
            ImportWizardView(draft: draft) {
                importDraft = nil
            }
            .environmentObject(store)
        }
    }

    private var transactionHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("История сделок")
                        .font(.largeTitle.weight(.semibold))
                    Text(exportedURL.map { "Последний экспорт: \($0.lastPathComponent)" } ?? "Операции, импорт брокерских CSV и экспорт журнала")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                transactionHeaderActions
            }

            VStack(alignment: .leading, spacing: 12) {
                pageHeader("История сделок", subtitle: exportedURL.map { "Последний экспорт: \($0.lastPathComponent)" } ?? "Операции, импорт брокерских CSV и экспорт журнала")
                transactionHeaderActions
            }
        }
    }

    private var transactionHeaderActions: some View {
        HStack(spacing: 10) {
            Button {
                selectCSVForImport()
            } label: {
                Label("Импорт CSV", systemImage: "tray.and.arrow.down")
            }

            Button {
                do {
                    exportedURL = try store.exportCSV()
                } catch {
                    store.lastRefreshError = "Не удалось экспортировать CSV: \(error.localizedDescription)"
                }
            } label: {
                Label("Экспорт CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(store.transactions.isEmpty)

            Button {
                isAddingTransaction = true
            } label: {
                Label("Добавить", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func delete(offsets: IndexSet) {
        let ids = offsets.map { store.transactionsNewestFirst[$0].id }
        store.deleteTransactions(withIDs: Set(ids))
    }

    private func selectCSVForImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                importDraft = try store.previewImportDraft(from: url)
            } catch {
                store.lastRefreshError = "Не удалось прочитать CSV: \(error.localizedDescription)"
            }
        }
    }
}

private struct TransactionRow: View {
    var transaction: InvestmentTransaction

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullRow
            compactRow
        }
        .monospacedDigit()
        .padding(.vertical, 8)
    }

    private var fullRow: some View {
        HStack(spacing: 16) {
            transactionIcon(size: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(transactionTitle)
                    .font(.headline)
                Text(transactionSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 220, alignment: .leading)

            Text(transaction.purchaseDate, format: AppFormatters.compactDate)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(transaction.kind.affectsPosition ? transaction.shares.formatted(AppFormatters.shares) : "-")
                    .font(.headline)
                Text(transaction.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 90, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 3) {
                Text(transaction.kind.affectsPosition ? transaction.purchasePrice.formatted(AppFormatters.price) : "-")
                    .font(.headline)
                Text("цена")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 3) {
                Text(transaction.displayAmount.formatted(AppFormatters.usd))
                    .font(.headline)
                Text("сумма")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 130, alignment: .trailing)
        }
    }

    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                transactionIcon(size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(transactionTitle)
                        .font(.headline)
                    Text(transactionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(transaction.displayAmount.formatted(AppFormatters.usd))
                    .font(.headline)
            }
            HStack(spacing: 12) {
                Text(transaction.purchaseDate, format: AppFormatters.compactDate)
                Text(transaction.kind.title)
                Text(transaction.kind.affectsPosition ? transaction.shares.formatted(AppFormatters.shares) : "-")
                Text(transaction.kind.affectsPosition ? transaction.purchasePrice.formatted(AppFormatters.price) : "-")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var transactionTitle: String {
        transaction.ticker.isEmpty ? transaction.kind.title : "\(transaction.kind.title) \(transaction.ticker)"
    }

    private var transactionSubtitle: String {
        if !transaction.companyName.isEmpty {
            return transaction.companyName
        }
        if !transaction.notes.isEmpty {
            return transaction.notes
        }
        return "Без названия"
    }

    @ViewBuilder
    private func transactionIcon(size: CGFloat) -> some View {
        if transaction.ticker.normalizedTicker.isEmpty {
            Image(systemName: transaction.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else {
            CompanyLogoView(ticker: transaction.ticker, size: size, cornerRadius: 8)
        }
    }
}
