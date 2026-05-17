import Charts
import SwiftUI

struct PortfolioHoldingsView: View {
    @EnvironmentObject private var store: PortfolioStore
    var filter: PortfolioFilter

    private var positions: [PortfolioPosition] {
        switch filter {
        case .longTermGrowth:
            return store.positions.filter { $0.gainLossPercent >= 0.08 }
        case .technology:
            return store.positions.filter { ["AAPL", "MSFT", "NVDA"].contains($0.ticker) }
        case .main:
            return store.positions
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader("Портфель", subtitle: "Состав, вес и результат по активам")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 300), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Стоимость", value: positions.reduce(0) { $0 + $1.marketValue }.formatted(AppFormatters.usd), detail: "\(positions.count) позиций", systemImage: "briefcase", tone: .accent)
                    MetricTile(title: "Прибыль", value: positions.reduce(0) { $0 + $1.gainLoss }.formatted(AppFormatters.usd), detail: "Нереализовано", systemImage: "arrow.up.right", tone: positions.reduce(0) { $0 + $1.gainLoss } >= 0 ? .positive : .negative)
                    MetricTile(title: "Кэш", value: store.cashBalance.formatted(AppFormatters.usd), detail: "Свободные деньги", systemImage: "wallet.pass")
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Позиции")
                            .font(.headline)
                        ForEach(positions) { position in
                            PositionSummaryRow(position: position, allocation: allocation(for: position))
                            if position.id != positions.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private func allocation(for position: PortfolioPosition) -> Double {
        let total = positions.reduce(0) { $0 + $1.marketValue }
        return total == 0 ? 0 : position.marketValue / total
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
                pageHeader("Аналитика", subtitle: "Распределение, лидеры и риск концентрации")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Активы", value: "\(store.positions.count)", detail: "В портфеле", systemImage: "square.grid.2x2")
                    MetricTile(title: "Лучший актив", value: bestPosition?.ticker ?? "-", detail: bestPosition?.gainLossPercent.formatted(AppFormatters.percent) ?? "-", systemImage: "trophy", tone: .positive)
                    MetricTile(title: "Реализовано", value: store.realizedGainLoss.formatted(AppFormatters.usd), detail: "От продаж", systemImage: "checkmark.seal")
                    MetricTile(title: "Кэш", value: store.cashBalance.formatted(AppFormatters.usd), detail: cashShare.formatted(AppFormatters.percent), systemImage: "banknote")
                }

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

    private func allocation(for position: PortfolioPosition) -> Double {
        store.securitiesMarketValue == 0 ? 0 : position.marketValue / store.securitiesMarketValue
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
}

struct NotificationsView: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader("Уведомления", subtitle: "Состояние данных и события, требующие внимания")

                GlassPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        NotificationRow(
                            icon: store.lastRefreshError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            title: store.lastRefreshError == nil ? "Котировки обновлены" : "Есть ошибка обновления",
                            detail: store.lastRefreshError ?? "Yahoo Finance cache доступен, данные сохранены локально.",
                            tone: store.lastRefreshError == nil ? .green : .orange
                        )
                        Divider()
                        NotificationRow(
                            icon: "externaldrive.fill",
                            title: "Локальное хранение",
                            detail: store.dataFilePath,
                            tone: .blue
                        )
                        Divider()
                        NotificationRow(
                            icon: store.cashBalance < 10 ? "banknote" : "banknote.fill",
                            title: store.cashBalance < 10 ? "Низкий свободный кэш" : "Кэш доступен",
                            detail: store.cashBalance.formatted(AppFormatters.usd),
                            tone: store.cashBalance < 10 ? .orange : .green
                        )
                    }
                }
            }
            .padding(22)
        }
    }
}

private func pageHeader(_ title: String, subtitle: String) -> some View {
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
