import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Binding var isAddingTransaction: Bool
    @State private var selectedTicker: String?
    @State private var selectedRange: ChartRange = .all
    @State private var selectedChartDate: Date?
    @State private var draftTransaction: InvestmentTransaction?
    @State private var assetDetailRoute: AssetDetailRoute?

    private var selectedPosition: PortfolioPosition? {
        let positions = store.positions
        return positions.first(where: { $0.ticker == selectedTicker }) ?? positions.first
    }

    var body: some View {
        Group {
            if store.transactions.isEmpty {
                EmptyPortfolioView(isAddingTransaction: $isAddingTransaction)
            } else {
                ScrollView {
                    mainDashboardContent
                        .padding(22)
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
        .sheet(item: $draftTransaction) { transaction in
            TransactionEditorView(draftTransaction: transaction)
                .environmentObject(store)
        }
        .sheet(item: $assetDetailRoute) { route in
            AssetDetailView(ticker: route.ticker)
                .environmentObject(store)
        }
    }

    private var mainDashboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            daySummary
            overviewActionPanel
            metrics
            chartPanel
            capitalStructurePanel
            holdingsPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                headerTitle

                Spacer()

                dataStatus
            }

            VStack(alignment: .leading, spacing: 6) {
                headerTitle
                dataStatus
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Обзор")
                .font(.largeTitle.weight(.semibold))
            Text("Сегодня, цель, динамика и состояние данных")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var dataStatus: some View {
        HStack(spacing: 7) {
            Label(dataFreshnessTitle, systemImage: dataFreshnessIcon)
                .foregroundStyle(dataFreshnessColor)
            Text("•")
                .foregroundStyle(.tertiary)
            Text(missingQuotesStatus)
                .foregroundStyle(store.dataHealthIssues.contains { $0.id == "missing-quotes" } ? .orange : .secondary)
            Text("•")
                .foregroundStyle(.tertiary)
            Text(latestBackupStatus)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .lineLimit(1)
    }

    private var daySummary: some View {
        GlassPanel {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    DashboardFactItem(title: "Итог дня", value: dayGain.formatted(AppFormatters.usd), detail: dayGainPercent.formatted(AppFormatters.percent), tone: dayGain >= 0 ? .green : .red)
                    Divider().frame(height: 34)
                    DashboardFactItem(title: "Плюс дня", value: bestDayMover?.ticker ?? "-", detail: bestDayMover?.amount.formatted(AppFormatters.usd) ?? "-", tone: .green)
                    Divider().frame(height: 34)
                    DashboardFactItem(title: "Минус дня", value: worstDayMover?.ticker ?? "-", detail: worstDayMover?.amount.formatted(AppFormatters.usd) ?? "-", tone: .red)
                    Divider().frame(height: 34)
                    DashboardFactItem(title: "Котировки", value: dataFreshnessShortTitle, detail: lastQuoteDateText, tone: dataFreshnessColor)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                    DashboardFactItem(title: "Итог дня", value: dayGain.formatted(AppFormatters.usd), detail: dayGainPercent.formatted(AppFormatters.percent), tone: dayGain >= 0 ? .green : .red)
                    DashboardFactItem(title: "Плюс дня", value: bestDayMover?.ticker ?? "-", detail: bestDayMover?.amount.formatted(AppFormatters.usd) ?? "-", tone: .green)
                    DashboardFactItem(title: "Минус дня", value: worstDayMover?.ticker ?? "-", detail: worstDayMover?.amount.formatted(AppFormatters.usd) ?? "-", tone: .red)
                    DashboardFactItem(title: "Котировки", value: dataFreshnessShortTitle, detail: lastQuoteDateText, tone: dataFreshnessColor)
                }
            }
        }
    }

    private var overviewActionPanel: some View {
        GlassPanel {
            let projection = store.financialGoalProjection
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    DashboardFactItem(title: "Цель", value: overviewGoalValue(projection), detail: overviewGoalDetail(projection), tone: overviewGoalTone(projection))
                    Divider().frame(height: 34)
                    DashboardFactItem(title: "Покупка", value: store.nextPlannedPurchase?.ticker ?? "-", detail: nextPurchaseOverviewText, tone: .blue)
                    Divider().frame(height: 34)
                    DashboardFactItem(title: "Дивиденды", value: store.nextExpectedDividend?.ticker ?? "-", detail: nextDividendOverviewText, tone: .green)
                    Divider().frame(height: 34)
                    DashboardFactItem(title: "Состояние", value: store.dataHealthIssues.isEmpty ? "ОК" : "\(store.dataHealthIssues.count)", detail: store.dataHealthIssues.first?.title ?? "данные согласованы", tone: store.dataHealthIssues.isEmpty ? .green : .orange)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                    DashboardFactItem(title: "Цель", value: overviewGoalValue(projection), detail: overviewGoalDetail(projection), tone: overviewGoalTone(projection))
                    DashboardFactItem(title: "Покупка", value: store.nextPlannedPurchase?.ticker ?? "-", detail: nextPurchaseOverviewText, tone: .blue)
                    DashboardFactItem(title: "Дивиденды", value: store.nextExpectedDividend?.ticker ?? "-", detail: nextDividendOverviewText, tone: .green)
                    DashboardFactItem(title: "Состояние", value: store.dataHealthIssues.isEmpty ? "ОК" : "\(store.dataHealthIssues.count)", detail: store.dataHealthIssues.first?.title ?? "данные согласованы", tone: store.dataHealthIssues.isEmpty ? .green : .orange)
                }
            }
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
            MetricTile(
                title: "Дивиденды",
                value: store.totalDividendsReceived.formatted(AppFormatters.usd),
                detail: "Всего получено",
                systemImage: "dollarsign.circle",
                tone: .positive
            )
        }
    }

    private var chartPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        chartTitle

                        Spacer()

                        chartControls
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        chartTitle
                        chartControls
                    }
                }

                Chart {
                    ForEach(chartHistory) { point in
                        AreaMark(
                            x: .value("Дата", point.date),
                            yStart: .value("Нижняя граница", chartYDomain.lowerBound),
                            yEnd: .value("Стоимость", point.marketValue)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    chartTone.opacity(0.24),
                                    chartTone.opacity(0.07),
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
                        .foregroundStyle(chartTone)
                        .lineStyle(.init(lineWidth: 2.7, lineCap: .round, lineJoin: .round))
                    }

                    if let selectedChartPoint {
                        RuleMark(x: .value("Дата", selectedChartPoint.date))
                            .foregroundStyle(.secondary.opacity(0.45))
                            .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                        PointMark(
                            x: .value("Дата", selectedChartPoint.date),
                            y: .value("Стоимость", selectedChartPoint.marketValue)
                        )
                        .foregroundStyle(chartTone)
                        .annotation(position: .top, alignment: .leading) {
                            ChartPointTooltip(point: selectedChartPoint)
                        }
                    }
                }
                .chartYScale(domain: chartYDomain)
                .chartXSelection(value: $selectedChartDate)
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

    private var chartTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Динамика портфеля")
                .font(.headline)
            HStack(spacing: 16) {
                Label(store.totalMarketValue.formatted(AppFormatters.usd), systemImage: "minus")
                    .foregroundStyle(chartTone)
                Text(chartPeriodChange.formatted(AppFormatters.percent))
                    .foregroundStyle(chartPeriodChange >= 0 ? .green : .red)
                    .monospacedDigit()
            }
            .font(.caption)
        }
    }

    private var chartControls: some View {
        Picker("Период", selection: $selectedRange) {
            ForEach(ChartRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 260)
    }

    private var capitalStructurePanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Структура капитала")
                        .font(.headline)
                    Spacer()
                    Text(store.totalMarketValue.formatted(AppFormatters.usd))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }

                GeometryReader { proxy in
                    HStack(spacing: 3) {
                        ForEach(capitalSlices) { slice in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(slice.color)
                                .frame(width: max(3, proxy.size.width * slice.share))
                        }
                    }
                }
                .frame(height: 10)

                HStack(spacing: 12) {
                    ForEach(capitalSlices) { slice in
                        CapitalLegend(slice: slice)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var holdingsPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Мои инвестиции")
                        .font(.headline)
                    Spacer()
                    Text("\(store.positions.count) активов")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                VStack(spacing: 0) {
                    PositionHeaderRow()
                        .padding(.horizontal, 10)
                    Divider().padding(.vertical, 2)
                    ForEach(store.positions) { position in
                        PositionRow(
                            position: position,
                            allocation: allocation(for: position),
                            isSelected: position.ticker == selectedPosition?.ticker
                        )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTicker = position.ticker
                                assetDetailRoute = AssetDetailRoute(ticker: position.ticker)
                            }
                            .contextMenu {
                                Button {
                                    draftTransaction = buyDraft(for: position)
                                } label: {
                                    Label("Купить", systemImage: "plus.circle")
                                }

                                Button {
                                    draftTransaction = dividendDraft(for: position)
                                } label: {
                                    Label("Дивиденд", systemImage: "dollarsign.circle")
                                }

                                Button {
                                    assetDetailRoute = AssetDetailRoute(ticker: position.ticker)
                                } label: {
                                    Label("Открыть детально", systemImage: "sidebar.right")
                                }
                            }
                        if position.id != store.positions.last?.id {
                            Divider()
                        }
                    }

                    Divider()
                    HStack {
                        Text("Итого по активам")
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
                    .padding(.horizontal, 10)
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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            CompanyLogoView(ticker: position.ticker, size: 42, cornerRadius: 12)

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

                        HStack(spacing: 8) {
                            Button {
                                draftTransaction = buyDraft(for: position)
                            } label: {
                                Label("Купить", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                draftTransaction = dividendDraft(for: position)
                            } label: {
                                Label("Дивиденд", systemImage: "dollarsign.circle")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                assetDetailRoute = AssetDetailRoute(ticker: position.ticker)
                            } label: {
                                Label("Detail", systemImage: "sidebar.right")
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
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
                        InspectorMetric("Сделок", "\(assetDetail(for: position)?.transactions.count ?? 0)")
                        InspectorMetric("Дивиденды", assetDetail(for: position)?.dividends.formatted(AppFormatters.usd) ?? "-", tone: .green)
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

    private var dayMovers: [DashboardMover] {
        store.positions.compactMap { position in
            guard let quote = store.quotesByTicker[position.ticker],
                  let previousClose = quote.previousClose
            else { return nil }
            let amount = position.shares * (quote.price - previousClose)
            return DashboardMover(ticker: position.ticker, amount: amount)
        }
    }

    private var bestDayMover: DashboardMover? {
        dayMovers.max { $0.amount < $1.amount }
    }

    private var worstDayMover: DashboardMover? {
        dayMovers.min { $0.amount < $1.amount }
    }

    private var latestQuoteDate: Date? {
        store.quotesByTicker.values.map(\.asOf).max()
    }

    private var lastQuoteDateText: String {
        guard let date = latestQuoteDate ?? store.marketDataRefreshedAt else { return "нет данных" }
        return date.formatted(AppFormatters.compactDate)
    }

    private var dataFreshnessTitle: String {
        dataIsFresh ? "Котировки свежие" : "Котировки устарели"
    }

    private var dataFreshnessShortTitle: String {
        dataIsFresh ? "Свежие" : "Устарели"
    }

    private var dataFreshnessIcon: String {
        dataIsFresh ? "checkmark.seal.fill" : "clock.badge.exclamationmark"
    }

    private var dataFreshnessColor: Color {
        dataIsFresh ? .green : .orange
    }

    private var dataIsFresh: Bool {
        guard let date = latestQuoteDate ?? store.marketDataRefreshedAt else { return false }
        let hours = Calendar.current.dateComponents([.hour], from: date, to: Date()).hour ?? 999
        return hours <= 36
    }

    private var missingQuotesStatus: String {
        let count = store.positions.filter { $0.currentPrice == nil }.count
        return count == 0 ? "все цены есть" : "без цены: \(count)"
    }

    private var latestBackupStatus: String {
        guard let backup = store.backupFiles.first else { return "бэкапа нет" }
        return "бэкап \(backup.createdAt.formatted(AppFormatters.compactDate))"
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

    private var chartYDomain: ClosedRange<Double> {
        let values = chartHistory.map(\.marketValue)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }
        let spread = maxValue - minValue
        let padding = max(spread * 0.18, maxValue * 0.015, 20)
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private var chartPeriodChange: Double {
        guard let first = chartHistory.first?.marketValue,
              let last = chartHistory.last?.marketValue,
              first > 0
        else { return 0 }
        return (last - first) / first
    }

    private var chartTone: Color {
        guard chartHistory.count >= 2 else { return .blue }
        if chartPeriodChange > 0 { return .green }
        if chartPeriodChange < 0 { return .red }
        return .blue
    }

    private var selectedChartPoint: PortfolioSnapshot? {
        guard let selectedChartDate else { return nil }
        return chartHistory.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(selectedChartDate)) < abs(rhs.date.timeIntervalSince(selectedChartDate))
        }
    }

    private var capitalSlices: [CapitalSlice] {
        store.capitalCompositionSlices.map { slice in
            CapitalSlice(
                title: slice.title,
                value: slice.value,
                color: slice.title == "Кэш" ? .green : .blue,
                share: slice.share
            )
        }
    }

    private var nextPurchaseOverviewText: String {
        guard let purchase = store.nextPlannedPurchase else { return "нет открытого плана" }
        return purchase.scheduledDate.formatted(AppFormatters.monthYear) + " • " + purchase.plannedAmount.formatted(AppFormatters.usd)
    }

    private var nextDividendOverviewText: String {
        guard let dividend = store.nextExpectedDividend else { return "нет истории выплат" }
        return dividend.expectedDate.formatted(AppFormatters.compactDate) + " • " + dividend.expectedAmount.formatted(AppFormatters.usd)
    }

    private func overviewGoalValue(_ projection: FinancialGoalProjection) -> String {
        switch projection.status {
        case .notConfigured:
            return "-"
        case .achieved:
            return "достигнута"
        case .reachable:
            return projection.projectedDate?.formatted(AppFormatters.monthYear) ?? "достижима"
        case .unreachable:
            return "не достигается"
        }
    }

    private func overviewGoalDetail(_ projection: FinancialGoalProjection) -> String {
        guard projection.targetValue > 0 else { return "цель не задана" }
        if projection.status == .achieved {
            return projection.currentValue.formatted(AppFormatters.usd)
        }
        if let months = projection.monthsToGoal {
            return "через \(months) мес."
        }
        return "осталось \(projection.gap.formatted(AppFormatters.usd))"
    }

    private func overviewGoalTone(_ projection: FinancialGoalProjection) -> Color {
        switch projection.status {
        case .notConfigured:
            return .secondary
        case .achieved:
            return .green
        case .reachable:
            return .blue
        case .unreachable:
            return .orange
        }
    }

    private func allocation(for position: PortfolioPosition) -> Double {
        store.securitiesMarketValue == 0 ? 0 : position.marketValue / store.securitiesMarketValue
    }

    private func assetDetail(for position: PortfolioPosition) -> AssetDetailSummary? {
        store.assetDetail(for: position.ticker)
    }

    private func buyDraft(for position: PortfolioPosition) -> InvestmentTransaction {
        InvestmentTransaction(
            kind: .buy,
            ticker: position.ticker,
            companyName: position.companyName,
            purchaseDate: Date(),
            shares: 0,
            purchasePrice: position.currentPrice ?? position.averageCost,
            commission: 0
        )
    }

    private func dividendDraft(for position: PortfolioPosition) -> InvestmentTransaction {
        InvestmentTransaction(
            kind: .dividend,
            ticker: position.ticker,
            companyName: position.companyName,
            purchaseDate: Date(),
            shares: 0,
            purchasePrice: 0,
            commission: 0,
            cashAmount: 0
        )
    }

    private func filteredPrices(for ticker: String, range: ChartRange) -> [HistoricalPrice] {
        let prices = store.priceHistoryByTicker[ticker.normalizedTicker] ?? []
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

private struct DashboardMover: Identifiable, Hashable {
    var id: String { ticker }
    var ticker: String
    var amount: Double
}

private struct CapitalSlice: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var value: Double
    var color: Color
    var share: Double
}

private struct DashboardFactItem: View {
    var title: String
    var value: String
    var detail: String
    var tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tone)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CapitalLegend: View {
    var slice: CapitalSlice

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(slice.color)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(slice.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(slice.value.formatted(AppFormatters.usd))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChartPointTooltip: View {
    var point: PortfolioSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(point.date, format: AppFormatters.compactDate)
                .font(.caption.weight(.semibold))
            tooltipRow("Стоимость", point.marketValue.formatted(AppFormatters.usd), tone: .primary)
            tooltipRow("Вложено", point.investedAmount.formatted(AppFormatters.usd), tone: .secondary)
            tooltipRow("Прибыль", point.gainLoss.formatted(AppFormatters.usd), tone: point.gainLoss >= 0 ? .green : .red)
            tooltipRow("%", point.gainLossPercent.formatted(AppFormatters.percent), tone: point.gainLoss >= 0 ? .green : .red)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func tooltipRow(_ title: String, _ value: String, tone: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(tone)
                .monospacedDigit()
        }
        .font(.caption2)
    }
}

private struct PositionHeaderRow: View {
    var body: some View {
        HStack {
            Text("Актив")
                .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
            Text("Цена").frame(width: 92, alignment: .trailing)
            Text("Кол-во").frame(width: 78, alignment: .trailing)
            Text("Стоимость").frame(width: 112, alignment: .trailing)
            Text("P/L").frame(width: 112, alignment: .trailing)
            Text("Доля").frame(width: 86, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}

private struct PositionRow: View {
    var position: PortfolioPosition
    var allocation: Double
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                CompanyLogoView(ticker: position.ticker, size: 30, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.ticker)
                        .font(.callout.weight(.semibold))
                    Text(position.companyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)

            Text((position.currentPrice ?? position.averageCost).formatted(AppFormatters.price))
                .foregroundStyle(position.hasLivePrice ? .primary : .secondary)
                .frame(width: 92, alignment: .trailing)

            Text(position.shares.formatted(AppFormatters.shares))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)

            Text(position.marketValue.formatted(AppFormatters.usd))
                .fontWeight(.semibold)
                .frame(width: 112, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 2) {
                Text(position.gainLoss.formatted(AppFormatters.usd))
                    .fontWeight(.semibold)
                Text(position.gainLossPercent.formatted(AppFormatters.percent))
                    .font(.caption2)
            }
            .foregroundStyle(position.gainLoss >= 0 ? .green : .red)
            .frame(width: 112, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 4) {
                Text(allocation.formatted(AppFormatters.percent))
                    .font(.caption.weight(.semibold))
                ProgressView(value: min(max(allocation, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(width: 56)
            }
            .frame(width: 86, alignment: .trailing)
        }
        .font(.callout)
        .monospacedDigit()
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
