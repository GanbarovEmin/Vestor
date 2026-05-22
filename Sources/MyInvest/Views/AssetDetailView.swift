import Charts
import SwiftUI

struct AssetDetailRoute: Identifiable, Hashable {
    var id: String { ticker }
    var ticker: String
}

struct AssetDetailView: View {
    @EnvironmentObject private var store: PortfolioStore
    var ticker: String
    @State private var draftTransaction: InvestmentTransaction?
    @State private var selectedRange: PortfolioChartRange = .year

    private var detail: AssetDetailSummary? {
        store.assetDetail(for: ticker)
    }

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 16) {
                    header(detail)
                    metrics(detail)
                    chart
                    dividends(detail)
                    transactions(detail)
                }
                .padding(22)
            } else {
                ContentUnavailableView("Актив не найден", systemImage: "magnifyingglass", description: Text(ticker))
                    .padding(40)
            }
        }
        .frame(minWidth: 720, minHeight: 620)
        .sheet(item: $draftTransaction) { transaction in
            TransactionEditorView(draftTransaction: transaction)
                .environmentObject(store)
        }
    }

    private func header(_ detail: AssetDetailSummary) -> some View {
        HStack(spacing: 14) {
            CompanyLogoView(ticker: detail.ticker, size: 46, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.ticker)
                    .font(.largeTitle.weight(.semibold))
                Text(detail.companyName)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                draftTransaction = InvestmentTransaction(kind: .buy, ticker: detail.ticker, companyName: detail.companyName, purchaseDate: Date(), shares: 0, purchasePrice: detail.currentPrice ?? 0, commission: 0)
            } label: {
                Label("Покупка", systemImage: "plus.circle")
            }
            Button {
                draftTransaction = InvestmentTransaction(kind: .dividend, ticker: detail.ticker, companyName: detail.companyName, purchaseDate: Date(), shares: 0, purchasePrice: 0, commission: 0, cashAmount: 0)
            } label: {
                Label("Дивиденд", systemImage: "dollarsign.circle")
            }
            Button {
                AppleStocksIntegration.openTicker(detail.ticker)
            } label: {
                Label("Открыть в Акциях", systemImage: "chart.line.uptrend.xyaxis")
            }
            .disabled(!AppleStocksIntegration.isAvailable)
            .help("Открыть \(detail.ticker) в приложении Акции")
        }
    }

    private func metrics(_ detail: AssetDetailSummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            MetricTile(title: "Цена", value: detail.currentPrice?.formatted(AppFormatters.price) ?? "-", detail: dayChangeText(detail), systemImage: "tag")
            MetricTile(title: "Средняя", value: detail.averageCost.formatted(AppFormatters.price), detail: detail.shares.formatted(AppFormatters.shares) + " шт.", systemImage: "sum")
            MetricTile(title: "Стоимость", value: detail.marketValue.formatted(AppFormatters.usd), detail: detail.allocation.formatted(AppFormatters.percent), systemImage: "briefcase")
            MetricTile(title: "Прибыль", value: detail.gainLoss.formatted(AppFormatters.usd), detail: detail.gainLossPercent.formatted(AppFormatters.percent), systemImage: "arrow.up.right", tone: detail.gainLoss >= 0 ? .positive : .negative)
            MetricTile(title: "Реализовано", value: detail.realizedGainLoss.formatted(AppFormatters.usd), detail: "от продаж", systemImage: "checkmark.seal", tone: detail.realizedGainLoss >= 0 ? .positive : .negative)
            MetricTile(title: "Дивиденды", value: detail.dividends.formatted(AppFormatters.usd), detail: "получено", systemImage: "dollarsign.circle", tone: .positive)
        }
    }

    private var chart: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("График цены")
                            .font(.headline)
                        Spacer()
                        rangePicker
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("График цены")
                            .font(.headline)
                        rangePicker
                    }
                }

                let prices = filteredPrices
                if prices.isEmpty {
                    ContentUnavailableView("Нет истории цены", systemImage: "chart.line.uptrend.xyaxis")
                        .frame(height: 180)
                } else {
                    Chart(prices) { price in
                        LineMark(x: .value("Дата", price.date), y: .value("Цена", price.close))
                            .foregroundStyle(.blue)
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                                .foregroundStyle(.secondary.opacity(0.10))
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount.formatted(AppFormatters.price))
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private var rangePicker: some View {
        Picker("Период", selection: $selectedRange) {
            ForEach(PortfolioChartRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 260)
    }

    private func transactions(_ detail: AssetDetailSummary) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Сделки")
                    .font(.headline)
                if detail.transactions.isEmpty {
                    Text("Операций по активу нет.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.transactions.prefix(12)) { transaction in
                        HStack {
                            Text(transaction.purchaseDate, format: AppFormatters.compactDate)
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            Text(transaction.kind.title)
                            Spacer()
                            Text(transaction.displayAmount.formatted(AppFormatters.usd))
                                .monospacedDigit()
                        }
                        if transaction.id != detail.transactions.prefix(12).last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func dividends(_ detail: AssetDetailSummary) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Дивиденды по активу")
                        .font(.headline)
                    Spacer()
                    Text(detail.dividends.formatted(AppFormatters.usd))
                        .font(.headline)
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }

                if detail.dividendTransactions.isEmpty {
                    Text("Выплат по этому активу пока нет.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.dividendTransactions.prefix(8)) { transaction in
                        HStack {
                            Text(transaction.purchaseDate, format: AppFormatters.compactDate)
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            Text(transaction.notes.isEmpty ? "Дивиденд" : transaction.notes)
                                .lineLimit(1)
                            Spacer()
                            Text(transaction.displayAmount.formatted(AppFormatters.usd))
                                .font(.headline)
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }
                        if transaction.id != detail.dividendTransactions.prefix(8).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func dayChangeText(_ detail: AssetDetailSummary) -> String {
        guard let change = detail.dayChange else { return "изменение за день" }
        if let percent = detail.dayChangePercent {
            return change.formatted(AppFormatters.usd) + " • " + percent.formatted(AppFormatters.percent)
        }
        return change.formatted(AppFormatters.usd)
    }

    private var filteredPrices: [HistoricalPrice] {
        let prices = store.priceHistoryByTicker[ticker.normalizedTicker] ?? []
        guard let cutoff = selectedRange.cutoffDate(relativeTo: prices.last?.date ?? Date()) else {
            return prices
        }
        let filtered = prices.filter { $0.date >= cutoff }
        return filtered.count >= 2 ? filtered : Array(prices.suffix(2))
    }
}

struct SearchResultsView: View {
    @EnvironmentObject private var store: PortfolioStore
    var query: String
    var onOpenAsset: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader("Поиск", subtitle: query)

                GlassPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.search(query)) { result in
                            Button {
                                if let ticker = result.ticker {
                                    onOpenAsset(ticker)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: result.systemImage)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.headline)
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            if result.id != store.search(query).last?.id { Divider() }
                        }

                        if store.search(query).isEmpty {
                            ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        }
                    }
                }
            }
            .padding(22)
        }
    }
}
