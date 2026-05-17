import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Binding var isAddingTransaction: Bool
    @State private var selectedTicker: String?
    @State private var selectedRange: ChartRange = .all

    private var selectedPosition: PortfolioPosition? {
        let positions = store.positions
        return positions.first(where: { $0.ticker == selectedTicker }) ?? positions.first
    }

    var body: some View {
        Group {
            if store.transactions.isEmpty {
                EmptyPortfolioView(isAddingTransaction: $isAddingTransaction)
            } else {
                GeometryReader { proxy in
                    if proxy.size.width >= 1260 {
                        HStack(spacing: 0) {
                            ScrollView {
                                mainDashboardContent
                                    .padding(22)
                            }

                            Divider()

                            positionInspector
                                .frame(width: 300)
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                mainDashboardContent
                                positionInspectorContent
                            }
                            .padding(18)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if store.isRefreshing {
                ProgressView("Обновляю котировки")
                    .controlSize(.small)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .liquidGlassSurface(cornerRadius: 14)
                    .padding(.top, 12)
            }
        }
    }

    private var mainDashboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            metrics
            chartPanel
            holdingsPanel
            recentPurchasesPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                headerTitle

                Spacer()

                if let lastDate = store.quotesByTicker.values.map(\.asOf).max() {
                    Text("Последнее закрытие \(lastDate, format: AppFormatters.compactDate)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                headerTitle
                if let lastDate = store.quotesByTicker.values.map(\.asOf).max() {
                    Text("Последнее закрытие \(lastDate, format: AppFormatters.compactDate)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Портфель")
                .font(.largeTitle.weight(.semibold))
            Text("Акции США, локальная история сделок и котировки Yahoo Finance")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 260), spacing: 12)], spacing: 12) {
            MetricTile(
                title: "Общая стоимость",
                value: store.totalMarketValue.formatted(AppFormatters.usd),
                detail: "\(store.positions.count) активов",
                systemImage: "chart.line.uptrend.xyaxis",
                tone: .accent
            )
            MetricTile(
                title: "Прибыль за все время",
                value: store.totalGainLoss.formatted(AppFormatters.usd),
                detail: store.totalGainLossPercent.formatted(AppFormatters.percent),
                systemImage: store.totalGainLoss >= 0 ? "arrow.up.right" : "arrow.down.right",
                tone: store.totalGainLoss >= 0 ? .positive : .negative
            )
            MetricTile(
                title: "Прибыль за день",
                value: dayGain.formatted(AppFormatters.usd),
                detail: dayGainPercent.formatted(AppFormatters.percent),
                systemImage: "sun.max",
                tone: dayGain >= 0 ? .positive : .negative
            )
            MetricTile(
                title: "Вложения",
                value: store.totalInvested.formatted(AppFormatters.usd),
                detail: "Себестоимость",
                systemImage: "creditcard"
            )
            MetricTile(
                title: "Доступно",
                value: store.cashBalance.formatted(AppFormatters.usd),
                detail: "Свободный кэш",
                systemImage: "wallet.pass"
            )
        }
    }

    private var chartPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Динамика портфеля")
                            .font(.headline)
                        HStack(spacing: 16) {
                            Label(store.securitiesMarketValue.formatted(AppFormatters.usd), systemImage: "minus")
                                .foregroundStyle(.blue)
                            Label(store.totalInvested.formatted(AppFormatters.usd), systemImage: "minus")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }

                    Spacer()

                    Picker("", selection: $selectedRange) {
                        ForEach(ChartRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                Chart(chartHistory) { point in
                    AreaMark(
                        x: .value("Дата", point.date),
                        yStart: .value("Ноль", 0),
                        yEnd: .value("Стоимость", point.marketValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .blue.opacity(0.20),
                                .blue.opacity(0.04),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Дата", point.date),
                        y: .value("Стоимость", point.marketValue)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .lineStyle(.init(lineWidth: 2.1, lineCap: .round, lineJoin: .round))

                    if point.id == chartHistory.last?.id {
                        PointMark(
                            x: .value("Дата", point.date),
                            y: .value("Стоимость", point.marketValue)
                        )
                        .foregroundStyle(.blue)
                        .annotation(position: .trailing, alignment: .center) {
                            Text(point.marketValue.formatted(AppFormatters.usd))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.blue, in: Capsule())
                        }
                    }
                }
                .chartYScale(domain: 0...chartUpperBound)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(.gray.opacity(0.18))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6))
                }
                .chartPlotStyle { plotArea in
                    plotArea.padding(.trailing, 70)
                }
                .frame(height: 300)
            }
        }
    }

    private var holdingsPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Мои инвестиции")
                    .font(.headline)

                VStack(spacing: 0) {
                    PositionHeaderRow()
                    Divider()
                    ForEach(store.positions) { position in
                        PositionRow(position: position, isSelected: position.ticker == selectedPosition?.ticker)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTicker = position.ticker
                            }
                        if position.id != store.positions.last?.id {
                            Divider()
                        }
                    }

                    Divider()
                    HStack {
                        Text("Всего активов")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(store.securitiesMarketValue.formatted(AppFormatters.usd))
                            .font(.headline)
                        Text(store.totalGainLoss.formatted(AppFormatters.usd))
                            .font(.headline)
                            .foregroundStyle(store.totalGainLoss >= 0 ? .green : .red)
                    }
                    .monospacedDigit()
                    .padding(.top, 10)
                }
            }
        }
    }

    private var recentPurchasesPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Последние сделки")
                    .font(.headline)

                ForEach(store.transactionsNewestFirst.prefix(5)) { transaction in
                    HStack {
                        Text(transaction.purchaseDate, format: AppFormatters.compactDate)
                            .frame(width: 120, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(transaction.ticker)
                            .font(.headline)
                            .frame(width: 70, alignment: .leading)
                        Text(transaction.companyName.isEmpty ? "Без названия" : transaction.companyName)
                            .lineLimit(1)
                        Spacer()
                        Text(transaction.kind.title)
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .leading)
                        Text(transaction.kind.affectsPosition ? transaction.shares.formatted(AppFormatters.shares) : "-")
                            .frame(width: 80, alignment: .trailing)
                        Text(transaction.kind.affectsPosition ? transaction.purchasePrice.formatted(AppFormatters.price) : transaction.displayAmount.formatted(AppFormatters.usd))
                            .frame(width: 130, alignment: .trailing)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var positionInspector: some View {
        ScrollView {
            positionInspectorContent
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var positionInspectorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let position = selectedPosition {
                GlassPanel {
                    HStack(alignment: .top, spacing: 12) {
                        tickerIcon(position.ticker)
                            .font(.system(size: 32))
                            .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(position.ticker)
                                .font(.title2.weight(.semibold))
                            Text(position.companyName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "star")
                            .foregroundStyle(.secondary)
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Текущая цена")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text((position.currentPrice ?? position.averageCost).formatted(AppFormatters.price))
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                            Spacer()
                            if let quote = store.quotesByTicker[position.ticker],
                               let dayChange = quote.dayChange,
                               let dayChangePercent = quote.dayChangePercent {
                                Text(dayChange.formatted(AppFormatters.usd) + " (" + dayChangePercent.formatted(AppFormatters.percent) + ")")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(dayChange >= 0 ? .green : .red)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                GlassPanel {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 12) {
                        InspectorMetric("Количество", position.shares.formatted(AppFormatters.shares))
                        InspectorMetric("Стоимость", position.marketValue.formatted(AppFormatters.usd))
                        InspectorMetric("Средняя", position.averageCost.formatted(AppFormatters.price))
                        InspectorMetric("Прибыль", position.gainLoss.formatted(AppFormatters.usd), tone: position.gainLoss >= 0 ? .green : .red)
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Доля в портфеле")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(allocation(for: position).formatted(AppFormatters.percent))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                            Spacer()
                            Gauge(value: allocation(for: position)) {}
                                .gaugeStyle(.accessoryCircularCapacity)
                                .tint(.blue)
                        }
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(position.ticker) за год")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Chart(filteredPrices(for: position.ticker, range: .year)) { price in
                            LineMark(
                                x: .value("Дата", price.date),
                                y: .value("Цена", price.close)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.blue)
                            .lineStyle(.init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .trailing)
                        }
                        .frame(height: 135)
                    }
                }

                Text("Yahoo Finance • цены в USD")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var dayGain: Double {
        store.positions.reduce(0) { partial, position in
            guard let quote = store.quotesByTicker[position.ticker],
                  let previousClose = quote.previousClose
            else { return partial }
            return partial + position.shares * (quote.price - previousClose)
        }
    }

    private var dayGainPercent: Double {
        let previousValue = store.securitiesMarketValue - dayGain
        return previousValue == 0 ? 0 : dayGain / previousValue
    }

    private var chartHistory: [PortfolioSnapshot] {
        let history = store.history
        guard let cutoff = selectedRange.cutoffDate(relativeTo: history.last?.date ?? Date()) else {
            return history
        }
        let filtered = history.filter { $0.date >= cutoff }
        if filtered.count >= 2 {
            return filtered
        }
        return Array(history.suffix(2))
    }

    private var chartUpperBound: Double {
        let peak = chartHistory.reduce(max(store.securitiesMarketValue, store.totalInvested)) { result, point in
            max(result, point.marketValue, point.investedAmount)
        }
        return max(1000, (peak * 1.12 / 1000).rounded(.up) * 1000)
    }

    private func allocation(for position: PortfolioPosition) -> Double {
        store.securitiesMarketValue == 0 ? 0 : position.marketValue / store.securitiesMarketValue
    }

    @ViewBuilder
    private func tickerIcon(_ ticker: String) -> some View {
        if ticker == "AAPL" {
            Image(systemName: "apple.logo")
        } else {
            Text(String(ticker.prefix(1)))
                .font(.title2.weight(.bold))
        }
    }

    private func filteredPrices(for ticker: String, range: ChartRange) -> [HistoricalPrice] {
        let prices = store.priceHistoryByTicker[ticker] ?? []
        guard let cutoff = range.cutoffDate(relativeTo: prices.last?.date ?? Date()) else {
            return prices
        }
        let filtered = prices.filter { $0.date >= cutoff }
        return filtered.count >= 2 ? filtered : Array(prices.suffix(2))
    }
}

private enum ChartRange: String, CaseIterable, Identifiable {
    case day
    case month
    case sixMonths
    case year
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "1Д"
        case .month: "1М"
        case .sixMonths: "6М"
        case .year: "1Г"
        case .all: "Все"
        }
    }

    func cutoffDate(relativeTo date: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: -7, to: date)
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: date)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: date)
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: date)
        case .all:
            return nil
        }
    }
}

private struct PositionHeaderRow: View {
    var body: some View {
        HStack {
            Text("Тикер").frame(width: 74, alignment: .leading)
            Text("Название").frame(width: 150, alignment: .leading)
            Text("Кол-во").frame(width: 70, alignment: .trailing)
            Text("Средняя").frame(width: 92, alignment: .trailing)
            Text("Текущая").frame(width: 92, alignment: .trailing)
            Text("Стоимость").frame(width: 104, alignment: .trailing)
            Text("Прибыль").frame(width: 104, alignment: .trailing)
            Text("%").frame(width: 66, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 7)
    }
}

private struct PositionRow: View {
    var position: PortfolioPosition
    var isSelected: Bool

    var body: some View {
        HStack {
            HStack(spacing: 9) {
                if position.ticker == "AAPL" {
                    Image(systemName: "apple.logo")
                } else {
                    Image(systemName: "building.2")
                }
                Text(position.ticker)
                    .font(.headline)
            }
            .frame(width: 74, alignment: .leading)

            Text(position.companyName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text(position.shares.formatted(AppFormatters.shares))
                .frame(width: 70, alignment: .trailing)
            Text(position.averageCost.formatted(AppFormatters.price))
                .frame(width: 92, alignment: .trailing)
            Text((position.currentPrice ?? position.averageCost).formatted(AppFormatters.price))
                .foregroundStyle(position.hasLivePrice ? .primary : .secondary)
                .frame(width: 92, alignment: .trailing)
            Text(position.marketValue.formatted(AppFormatters.usd))
                .frame(width: 104, alignment: .trailing)
            Text(position.gainLoss.formatted(AppFormatters.usd))
                .foregroundStyle(position.gainLoss >= 0 ? .green : .red)
                .frame(width: 104, alignment: .trailing)
            Text(position.gainLossPercent.formatted(AppFormatters.percent))
                .foregroundStyle(position.gainLoss >= 0 ? .green : .red)
                .frame(width: 66, alignment: .trailing)
        }
        .font(.callout)
        .monospacedDigit()
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct InspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct InspectorMetric: View {
    var title: String
    var value: String
    var tone: Color = .primary

    init(_ title: String, _ value: String, tone: Color = .primary) {
        self.title = title
        self.value = value
        self.tone = tone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tone)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
