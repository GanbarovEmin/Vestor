import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Binding var isAddingTransaction: Bool

    var body: some View {
        VStack(spacing: 0) {
            if store.transactions.isEmpty {
                EmptyPortfolioView(isAddingTransaction: $isAddingTransaction)
            } else {
                List {
                    ForEach(store.transactionsNewestFirst) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.inset)
            }
        }
    }

    private func delete(offsets: IndexSet) {
        let ids = offsets.map { store.transactionsNewestFirst[$0].id }
        store.deleteTransactions(withIDs: Set(ids))
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
            Image(systemName: transaction.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)

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
                Image(systemName: transaction.kind.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
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
}
