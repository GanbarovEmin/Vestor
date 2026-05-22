import Charts
import SwiftUI

private struct PortfolioDayMover: Identifiable, Hashable {
    var id: String { ticker }
    var ticker: String
    var amount: Double
    var percent: Double
}

private struct CompactMoverRow: View {
    var title: String
    var mover: PortfolioDayMover?
    var fallbackTone: Color

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(mover?.ticker ?? "-")
                    .font(.callout.weight(.semibold))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(mover?.amount.formatted(AppFormatters.usd) ?? "-")
                    .font(.callout.weight(.semibold))
                Text(mover?.percent.formatted(AppFormatters.percent) ?? "-")
                    .font(.caption2)
            }
            .foregroundStyle(mover.map { $0.amount >= 0 ? Color.green : Color.red } ?? fallbackTone)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

struct DividendsView: View {
    @EnvironmentObject private var store: PortfolioStore

    private var dividends: [InvestmentTransaction] {
        store.dividendTransactions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader("Дивиденды", subtitle: "Денежные выплаты по активам")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 300), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Всего получено", value: store.totalDividendsReceived.formatted(AppFormatters.usd), detail: "\(dividends.count) выплат", systemImage: "dollarsign.circle", tone: .positive)
                    MetricTile(title: "Последняя выплата", value: (dividends.first?.displayAmount ?? 0).formatted(AppFormatters.usd), detail: dividends.first?.ticker.isEmpty == false ? dividends.first?.ticker ?? "-" : "-", systemImage: "calendar")
                    MetricTile(title: "Див. доходность", value: dividendYield.formatted(AppFormatters.percent), detail: "К стоимости активов", systemImage: "percent")
                }

                nextDividendPanel

                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("История выплат")
                            .font(.headline)
                        if dividends.isEmpty {
                            ContentUnavailableView("Дивидендов пока нет", systemImage: "dollarsign.circle", description: Text("Когда появятся операции Дивиденд, они будут показаны здесь."))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(dividends) { item in
                                TransactionCompactRow(transaction: item)
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private var dividendYield: Double {
        let total = store.securitiesMarketValue
        return total == 0 ? 0 : store.totalDividendsReceived / total
    }

    @ViewBuilder
    private var nextDividendPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Следующая выплата")
                    .font(.headline)

                if let next = store.nextExpectedDividend {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            nextDividendIdentity(next)
                            Spacer()
                            nextDividendDateAndAmount(next)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            nextDividendIdentity(next)
                            nextDividendDateAndAmount(next)
                        }
                    }
                } else {
                    ContentUnavailableView("Нет истории выплат", systemImage: "calendar.badge.clock", description: Text("Добавьте дивиденды в историю, чтобы увидеть следующую ожидаемую дату."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
        }
    }

    private func nextDividendIdentity(_ next: DividendPaymentSummary) -> some View {
        HStack(spacing: 12) {
            CompanyLogoView(ticker: next.ticker, size: 38, cornerRadius: 11)
            VStack(alignment: .leading, spacing: 3) {
                Text(next.ticker)
                    .font(.headline)
                Text(next.companyName.isEmpty ? "Без названия" : next.companyName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Оценка по истории выплат")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func nextDividendDateAndAmount(_ next: DividendPaymentSummary) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(next.expectedDate, format: AppFormatters.compactDate)
                    .font(.headline)
                Text("дата")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(next.expectedAmount.formatted(AppFormatters.usd))
                    .font(.headline)
                    .foregroundStyle(.green)
                    .monospacedDigit()
                Text("сумма")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AnalyticsView: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader("Аналитика", subtitle: "Результат портфеля, распределение, лидеры и дневные движения")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Активы", value: "\(store.positions.count)", detail: "В портфеле", systemImage: "square.grid.2x2")
                    MetricTile(title: "Лучший актив", value: bestPosition?.ticker ?? "-", detail: bestPosition?.gainLossPercent.formatted(AppFormatters.percent) ?? "-", systemImage: "trophy", tone: .positive)
                    MetricTile(title: "Реализовано", value: store.realizedGainLoss.formatted(AppFormatters.usd), detail: "От продаж", systemImage: "checkmark.seal")
                    MetricTile(title: "Кэш", value: store.cashBalance.formatted(AppFormatters.usd), detail: cashShare.formatted(AppFormatters.percent), systemImage: "banknote")
                }

                performancePanel
                dailyMoversPanel

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        allocationChart
                        profitLeaders
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        allocationChart
                        profitLeaders
                    }
                }

                riskPanel
            }
            .padding(22)
        }
    }

    private var bestPosition: PortfolioPosition? {
        store.positions.max { $0.gainLossPercent < $1.gainLossPercent }
    }

    private var cashShare: Double {
        store.totalMarketValue == 0 ? 0 : store.cashBalance / store.totalMarketValue
    }

    private var dayMovers: [PortfolioDayMover] {
        store.positions.compactMap { position in
            guard let quote = store.quotesByTicker[position.ticker],
                  let previousClose = quote.previousClose,
                  previousClose > 0
            else { return nil }

            let priceChange = quote.price - previousClose
            return PortfolioDayMover(
                ticker: position.ticker,
                amount: position.shares * priceChange,
                percent: priceChange / previousClose
            )
        }
    }

    private var bestDayMover: PortfolioDayMover? {
        dayMovers.max { $0.percent < $1.percent }
    }

    private var worstDayMover: PortfolioDayMover? {
        dayMovers.min { $0.percent < $1.percent }
    }

    private var largestPositiveContributor: PortfolioDayMover? {
        dayMovers.max { $0.amount < $1.amount }
    }

    private var performancePanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Результат портфеля")
                    .font(.headline)
                let summary = store.performanceSummary
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    AnalyticsReturnMetric(title: "Стоимость", value: summary.currentValue.formatted(AppFormatters.usd), tone: .primary)
                    AnalyticsReturnMetric(title: "Вложено", value: summary.investedAmount.formatted(AppFormatters.usd), tone: .secondary)
                    AnalyticsReturnMetric(title: "Нереализованная прибыль", value: summary.unrealizedGainLoss.formatted(AppFormatters.usd), tone: summary.unrealizedGainLoss >= 0 ? .green : .red)
                    AnalyticsReturnMetric(title: "Реализовано", value: summary.realizedGainLoss.formatted(AppFormatters.usd), tone: summary.realizedGainLoss >= 0 ? .green : .red)
                    AnalyticsReturnMetric(title: "Дивиденды", value: summary.dividends.formatted(AppFormatters.usd), tone: .green)
                    AnalyticsReturnMetric(title: "Кэш", value: summary.cash.formatted(AppFormatters.usd), tone: .blue)
                }
            }
        }
    }

    private func allocation(for position: PortfolioPosition) -> Double {
        store.securitiesMarketValue == 0 ? 0 : position.marketValue / store.securitiesMarketValue
    }

    private var dailyMoversPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Движение за день", systemImage: "arrow.up.arrow.down")
                        .font(.headline)
                    Spacer()
                    Text(dayMovers.isEmpty ? "нет данных" : "\(dayMovers.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if dayMovers.isEmpty {
                    Text("Для расчета нужны текущая цена и previous close по активам.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    CompactMoverRow(title: "Плюс дня", mover: bestDayMover, fallbackTone: .green)
                    Divider()
                    CompactMoverRow(title: "Минус дня", mover: worstDayMover, fallbackTone: .red)
                    Divider()
                    CompactMoverRow(title: "Вклад в итог дня", mover: largestPositiveContributor, fallbackTone: .green)
                }
            }
        }
    }

    private var allocationChart: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Распределение по активам")
                    .font(.headline)
                Chart(store.positions) { position in
                    SectorMark(
                        angle: .value("Стоимость", position.marketValue),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Тикер", position.ticker))
                }
                .frame(height: 260)
            }
        }
    }

    private var profitLeaders: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Лидеры прибыли")
                    .font(.headline)
                let leaders = store.positions.sorted { $0.gainLoss > $1.gainLoss }.prefix(5)
                ForEach(Array(leaders)) { position in
                    PositionSummaryRow(position: position, allocation: allocation(for: position))
                    if position.id != leaders.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var riskPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Риск концентрации")
                    .font(.headline)

                let sorted = store.positions.sorted { allocation(for: $0) > allocation(for: $1) }
                ForEach(Array(sorted.prefix(5))) { position in
                    HStack {
                        CompanyLogoView(ticker: position.ticker, size: 26, cornerRadius: 8)
                        Text(position.ticker)
                            .font(.headline)
                        Spacer()
                        Text(allocation(for: position).formatted(AppFormatters.percent))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(allocation(for: position) > 0.25 ? .orange : .primary)
                    }
                    .padding(.vertical, 6)
                    if position.id != sorted.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct AnalyticsReturnMetric: View {
    var title: String
    var value: String
    var tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(tone)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader("Уведомления", subtitle: "События, риски и состояние локальных данных")

                GlassPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("События")
                                .font(.headline)
                            Spacer()
                            Button {
                                Task {
                                    await LocalNotificationService.schedulePortfolioNotifications(
                                        alerts: store.alerts,
                                        nextDividend: store.nextExpectedDividend
                                    )
                                }
                            } label: {
                                Label("Включить macOS", systemImage: "bell.badge")
                            }
                        }
                        ForEach(store.alerts) { alert in
                            NotificationRow(icon: alert.icon, title: alert.title, detail: alert.detail, tone: alert.severity.color)
                            if alert.id != store.alerts.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Data Health")
                            .font(.headline)

                        NotificationRow(
                            icon: "externaldrive.fill",
                            title: "Локальное хранение",
                            detail: store.dataFilePath,
                            tone: .blue
                        )

                        Divider()

                        if store.dataHealthIssues.isEmpty {
                            NotificationRow(
                                icon: "checkmark.seal.fill",
                                title: "Проверка данных без замечаний",
                                detail: "Операции, котировки и бэкапы выглядят согласованно.",
                                tone: .green
                            )
                        } else {
                            ForEach(store.dataHealthIssues) { issue in
                                NotificationRow(icon: issue.icon, title: issue.title, detail: issue.detail, tone: issue.severity.color)
                                if issue.id != store.dataHealthIssues.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
    }
}

func pageHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title)
            .font(.largeTitle.weight(.semibold))
        Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private struct PositionSummaryRow: View {
    var position: PortfolioPosition
    var allocation: Double

    var body: some View {
        HStack(spacing: 12) {
            CompanyLogoView(ticker: position.ticker, size: 28, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(position.ticker)
                    .font(.headline)
                Text(position.companyName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.marketValue.formatted(AppFormatters.usd))
                    .font(.headline)
                Text(allocation.formatted(AppFormatters.percent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.gainLoss.formatted(AppFormatters.usd))
                    .font(.headline)
                    .foregroundStyle(position.gainLoss >= 0 ? .green : .red)
                Text(position.gainLossPercent.formatted(AppFormatters.percent))
                    .font(.caption)
                    .foregroundStyle(position.gainLoss >= 0 ? .green : .red)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.vertical, 8)
    }
}

private struct TransactionCompactRow: View {
    var transaction: InvestmentTransaction

    var body: some View {
        HStack {
            if transaction.ticker.isEmpty {
                Image(systemName: transaction.kind.systemImage)
                    .foregroundStyle(.blue)
                    .frame(width: 28)
            } else {
                CompanyLogoView(ticker: transaction.ticker, size: 28, cornerRadius: 8)
            }
            Text(transaction.purchaseDate, format: AppFormatters.compactDate)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(transaction.ticker.isEmpty ? transaction.kind.title : transaction.ticker)
                .font(.headline)
            Text(transaction.companyName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(transaction.displayAmount.formatted(AppFormatters.usd))
                .font(.headline)
                .monospacedDigit()
        }
        .padding(.vertical, 7)
    }
}

private struct NotificationRow: View {
    var icon: String
    var title: String
    var detail: String
    var tone: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tone)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
