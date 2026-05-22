import Charts
import SwiftUI

struct GoalsView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var targetPortfolioValue = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader("Цели", subtitle: "Финансовая цель и прогноз достижения")
                financialGoalPanel
                projectionChartPanel
                projectionFactorsPanel
            }
            .padding(22)
        }
        .onAppear {
            targetPortfolioValue = store.portfolioGoal.targetPortfolioValue == 0 ? "" : store.portfolioGoal.targetPortfolioValue.formatted(.number.precision(.fractionLength(0...2)))
        }
    }

    private var financialGoalPanel: some View {
        GlassPanel {
            let projection = store.financialGoalProjection
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        goalTitle(projection)
                        Spacer()
                        targetValueControls
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        goalTitle(projection)
                        targetValueControls
                    }
                }

                ProgressView(value: projection.progress)
                    .tint(projection.status == .unreachable ? .orange : .green)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                    GoalMetric(title: "Сейчас", value: projection.currentValue.formatted(AppFormatters.usd), tone: .primary)
                    GoalMetric(title: "Цель", value: projection.targetValue > 0 ? projection.targetValue.formatted(AppFormatters.usd) : "-", tone: .accentColor)
                    GoalMetric(title: "Осталось", value: projection.gap.formatted(AppFormatters.usd), tone: projection.gap == 0 ? .green : .orange)
                    GoalMetric(title: "Прогноз", value: goalDateText(projection), tone: goalDateTone(projection))
                }
            }
        }
    }

    @ViewBuilder
    private var projectionChartPanel: some View {
        let projection = store.financialGoalProjection
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Потенциальный рост")
                            .font(.headline)
                        Text("Базовая кривая: текущая стоимость, сложный процент, реинвестированные дивиденды и покупки из очереди.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(goalDateText(projection))
                        .font(.headline)
                        .foregroundStyle(goalDateTone(projection))
                        .monospacedDigit()
                }

                if projection.projectedPoints.count < 2 || projection.status == .notConfigured {
                    ContentUnavailableView(
                        "Нет прогноза",
                        systemImage: "target",
                        description: Text("Введите желаемую сумму портфеля, чтобы построить кривую роста.")
                    )
                    .frame(height: 260)
                } else {
                    Chart {
                        ForEach(projection.projectedPoints) { point in
                            AreaMark(
                                x: .value("Месяц", point.date),
                                yStart: .value("Нижняя граница", goalChartYDomain(projection).lowerBound),
                                yEnd: .value("Стоимость", point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(goalDateTone(projection).opacity(0.16))

                            LineMark(
                                x: .value("Месяц", point.date),
                                y: .value("Стоимость", point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(goalDateTone(projection))
                        }

                        if projection.targetValue > 0 {
                            RuleMark(y: .value("Цель", projection.targetValue))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                .foregroundStyle(.secondary.opacity(0.45))
                        }
                    }
                    .chartYScale(domain: goalChartYDomain(projection))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine()
                                .foregroundStyle(.secondary.opacity(0.12))
                            AxisValueLabel(format: .dateTime.month(.abbreviated).year())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                                .foregroundStyle(.secondary.opacity(0.10))
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount.formatted(AppFormatters.usd))
                                }
                            }
                        }
                    }
                    .frame(height: 280)
                }
            }
        }
    }

    private var projectionFactorsPanel: some View {
        let projection = store.financialGoalProjection
        return GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Почему такой прогноз")
                        .font(.headline)
                    Text(projection.reasonText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 10)], spacing: 10) {
                    assumptionRow(
                        title: "Текущий портфель",
                        value: projection.currentValue.formatted(AppFormatters.usd),
                        detail: "активы + кэш"
                    )
                    assumptionRow(
                        title: "Остаток до цели",
                        value: projection.gap.formatted(AppFormatters.usd),
                        detail: projection.progress.formatted(AppFormatters.percent) + " уже набрано"
                    )
                    assumptionRow(
                        title: "Рост по истории",
                        value: projection.annualGrowthRate.formatted(AppFormatters.percent),
                        detail: "annualized TWR"
                    )
                    assumptionRow(
                        title: "Дивиденды",
                        value: projection.dividendYield.formatted(AppFormatters.percent),
                        detail: "реинвестируются"
                    )
                    assumptionRow(
                        title: "Очередь покупок",
                        value: projection.plannedContributionTotal.formatted(AppFormatters.usd),
                        detail: "\(store.openPlannedPurchases.count) открытых пунктов"
                    )
                    assumptionRow(
                        title: "Эффективный темп",
                        value: projection.effectiveAnnualRate.formatted(AppFormatters.percent),
                        detail: "рост + дивиденды"
                    )
                }

                Divider()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 10)], spacing: 10) {
                    assumptionRow(
                        title: "Покупки в прогнозе",
                        value: projection.plannedContributionUsed.formatted(AppFormatters.usd),
                        detail: "учтены до даты прогноза"
                    )
                    assumptionRow(
                        title: "Вклад роста",
                        value: projection.contributionGrowth.formatted(AppFormatters.usd),
                        detail: "сложный процент"
                    )
                    assumptionRow(
                        title: "Вклад дивидендов",
                        value: projection.contributionDividends.formatted(AppFormatters.usd),
                        detail: "реинвестирование"
                    )
                }
            }
        }
    }

    private func goalTitle(_ projection: FinancialGoalProjection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Финансовая цель")
                .font(.headline)
            Text(goalStatusText(projection))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var targetValueControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                TextField("Желаемая сумма портфеля", text: $targetPortfolioValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("Сохранить", action: saveTargetValue)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Желаемая сумма портфеля", text: $targetPortfolioValue)
                    .textFieldStyle(.roundedBorder)
                Button("Сохранить", action: saveTargetValue)
            }
        }
    }

    private func saveTargetValue() {
        var goal = store.portfolioGoal
        goal.targetPortfolioValue = parsedAmount(targetPortfolioValue)
        store.updatePortfolioGoal(goal)
    }

    private func parsedAmount(_ text: String) -> Double {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
        return max(0, Double(normalized) ?? 0)
    }

    private func goalStatusText(_ projection: FinancialGoalProjection) -> String {
        switch projection.status {
        case .notConfigured:
            return "Введите желаемую сумму портфеля, чтобы увидеть прогноз."
        case .achieved:
            return "Цель уже достигнута текущей стоимостью портфеля."
        case .reachable:
            guard let months = projection.monthsToGoal else {
                return "Цель достижима текущими темпами."
            }
            return "Текущими темпами цель будет достигнута через \(months) мес."
        case .unreachable:
            return "При текущем темпе и открытой очереди цель не достигается."
        }
    }

    private func goalDateText(_ projection: FinancialGoalProjection) -> String {
        switch projection.status {
        case .notConfigured:
            return "-"
        case .achieved:
            return "достигнута"
        case .reachable:
            guard let date = projection.projectedDate else { return "достижима" }
            return date.formatted(AppFormatters.monthYear)
        case .unreachable:
            return "не достигается"
        }
    }

    private func goalDateTone(_ projection: FinancialGoalProjection) -> Color {
        switch projection.status {
        case .achieved:
            return .green
        case .reachable:
            return .blue
        case .unreachable:
            return .orange
        case .notConfigured:
            return .secondary
        }
    }

    private func goalChartYDomain(_ projection: FinancialGoalProjection) -> ClosedRange<Double> {
        let values = projection.projectedPoints.map(\.value) + (projection.targetValue > 0 ? [projection.targetValue] : [])
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        let spread = max(1, maxValue - minValue)
        let padding = spread * 0.08
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private func assumptionRow(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct GoalMetric: View {
    var title: String
    var value: String
    var tone: Color = .primary

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
