import Combine
import Foundation

@MainActor
final class PortfolioStore: ObservableObject {
    @Published private(set) var transactions: [InvestmentTransaction] = []
    @Published private(set) var quotesByTicker: [String: MarketQuote] = [:]
    @Published private(set) var priceHistoryByTicker: [String: [HistoricalPrice]] = [:]
    @Published private(set) var companyProfilesByTicker: [String: CompanyProfile] = [:]
    @Published private(set) var plannedPurchases: [PlannedPurchase] = []
    @Published private(set) var backupFiles: [BackupFile] = []
    @Published private(set) var setupState = AppSetupState()
    @Published private(set) var importPresets: [ImportPreset] = []
    @Published private(set) var changeJournal: [ChangeJournalEntry] = []
    @Published private(set) var portfolioGoal = PortfolioGoal()
    @Published private(set) var positions: [PortfolioPosition] = []
    @Published private(set) var history: [PortfolioSnapshot] = []
    @Published private(set) var transactionsNewestFirst: [InvestmentTransaction] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var marketDataRefreshedAt: Date?
    @Published var lastRefreshError: String?
    @Published var yahooCookieHeader: String {
        didSet {
            KeychainService.save(yahooCookieHeader, service: Self.keychainService, account: "yahooCookieHeader")
        }
    }

    private let fileURL: URL
    private let plannedPurchasesURL: URL
    private let setupURL: URL
    private let importPresetsURL: URL
    private let journalURL: URL
    private let goalsURL: URL
    private let cacheStore: MarketDataCacheStore

    init(
        fileURL: URL = PortfolioStore.defaultFileURL,
        plannedPurchasesURL: URL = PortfolioStore.defaultPlannedPurchasesURL,
        setupURL: URL = PortfolioStore.defaultSetupURL,
        importPresetsURL: URL = PortfolioStore.defaultImportPresetsURL,
        journalURL: URL = PortfolioStore.defaultJournalURL,
        goalsURL: URL = PortfolioStore.defaultGoalsURL,
        cacheURL: URL = PortfolioStore.defaultCacheURL
    ) {
        self.fileURL = fileURL
        self.plannedPurchasesURL = plannedPurchasesURL
        self.setupURL = setupURL
        self.importPresetsURL = importPresetsURL
        self.journalURL = journalURL
        self.goalsURL = goalsURL
        self.cacheStore = MarketDataCacheStore(fileURL: cacheURL)
        self.yahooCookieHeader = KeychainService.read(service: Self.keychainService, account: "yahooCookieHeader")
        loadSetupState()
        loadImportPresets()
        loadChangeJournal()
        loadPortfolioGoal()
        load()
        loadPlannedPurchases()
        loadMarketDataCache()
        refreshPortfolioSnapshots()
        refreshBackupFiles()
    }

    var totalMarketValue: Double {
        securitiesMarketValue + cashBalance
    }

    var securitiesMarketValue: Double {
        positions.reduce(0) { $0 + $1.marketValue }
    }

    var totalInvested: Double {
        positions.reduce(0) { $0 + $1.costBasis }
    }

    var totalGainLoss: Double {
        securitiesMarketValue - totalInvested
    }

    var totalGainLossPercent: Double {
        totalInvested == 0 ? 0 : totalGainLoss / totalInvested
    }

    var dataFilePath: String {
        fileURL.path
    }

    var cashBalance: Double {
        transactions.reduce(0) { $0 + $1.cashImpact }
    }

    var realizedGainLoss: Double {
        positions.reduce(0) { $0 + $1.realizedGainLoss }
    }

    var dividendTransactions: [InvestmentTransaction] {
        transactions.filter { $0.kind == .dividend }.sorted { $0.purchaseDate > $1.purchaseDate }
    }

    var totalDividendsReceived: Double {
        dividendTransactions.reduce(0) { $0 + $1.displayAmount }
    }

    var nextExpectedDividend: DividendPaymentSummary? {
        let grouped = Dictionary(grouping: dividendTransactions.filter { !$0.ticker.normalizedTicker.isEmpty }) {
            $0.ticker.normalizedTicker
        }
        let today = Date().startOfDay

        return grouped.compactMap { ticker, dividends -> DividendPaymentSummary? in
            let sorted = dividends.sorted { $0.purchaseDate < $1.purchaseDate }
            guard let latest = sorted.last else { return nil }
            let interval = estimatedDividendIntervalDays(from: sorted)
            var nextDate = Calendar.current.date(byAdding: .day, value: interval, to: latest.purchaseDate) ?? latest.purchaseDate
            while nextDate < today {
                nextDate = Calendar.current.date(byAdding: .day, value: interval, to: nextDate) ?? today
            }

            return DividendPaymentSummary(
                ticker: ticker,
                companyName: bestCompanyName(for: ticker) ?? latest.companyName,
                expectedDate: nextDate.startOfDay,
                expectedAmount: latest.displayAmount
            )
        }
        .sorted { $0.expectedDate < $1.expectedDate }
        .first
    }

    var openPlannedPurchases: [PlannedPurchase] {
        plannedPurchases.filter { !$0.isCompleted }.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var completedPlannedPurchases: [PlannedPurchase] {
        plannedPurchases.filter(\.isCompleted).sorted { $0.scheduledDate > $1.scheduledDate }
    }

    var plannedPurchaseTotal: Double {
        openPlannedPurchases.reduce(0) { $0 + $1.plannedAmount }
    }

    var capitalCompositionSlices: [CapitalCompositionSlice] {
        let rawSlices = [
            ("Активы", max(0, securitiesMarketValue)),
            ("Кэш", max(0, cashBalance))
        ].filter { $0.1 > 0.000001 }
        let total = max(1, rawSlices.reduce(0) { $0 + $1.1 })
        return rawSlices.map { title, value in
            CapitalCompositionSlice(title: title, value: value, share: value / total)
        }
    }

    var nextPlannedPurchase: PlannedPurchase? {
        openPlannedPurchases.first
    }

    var marketDataTickers: Set<String> {
        Set(transactions
            .filter(\.kind.affectsPosition)
            .map(\.ticker.normalizedTicker)
            .filter { !$0.isEmpty })
    }

    var backupDirectoryURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    var exportDirectoryURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Exports", isDirectory: true)
    }

    var performanceSummary: PortfolioPerformanceSummary {
        PortfolioPerformanceSummary(
            currentValue: totalMarketValue,
            investedAmount: totalInvested,
            unrealizedGainLoss: totalGainLoss,
            realizedGainLoss: realizedGainLoss,
            dividends: totalDividendsReceived,
            cash: cashBalance,
            gainLossPercent: totalGainLossPercent
        )
    }

    var dayMovementSummary: PortfolioDayMovementSummary {
        let movers = positions.compactMap { position -> PortfolioDayMover? in
            guard let quote = quotesByTicker[position.ticker],
                  let previousClose = quote.previousClose,
                  previousClose > 0
            else { return nil }

            let priceChange = quote.price - previousClose
            return PortfolioDayMover(
                ticker: position.ticker,
                companyName: position.companyName,
                amount: position.shares * priceChange,
                percent: priceChange / previousClose,
                priceChange: priceChange
            )
        }
        .sorted { abs($0.amount) > abs($1.amount) }

        guard !movers.isEmpty else { return .empty }

        let totalAmount = movers.reduce(0) { $0 + $1.amount }
        let previousValue = securitiesMarketValue - totalAmount
        let totalPercent = previousValue == 0 ? 0 : totalAmount / previousValue

        return PortfolioDayMovementSummary(
            movers: movers,
            totalAmount: totalAmount,
            totalPercent: totalPercent,
            bestByPercent: movers.max { $0.percent < $1.percent },
            worstByPercent: movers.min { $0.percent < $1.percent },
            largestDollarContributor: movers.max { abs($0.amount) < abs($1.amount) }
        )
    }

    var projectedPlanSnapshots: [ProjectedPlanSnapshot] {
        [6, 12, 24].map { horizon in
            let cutoff = Calendar.current.date(byAdding: .month, value: horizon, to: Date()) ?? Date()
            let futurePurchases = openPlannedPurchases.filter { $0.scheduledDate <= cutoff }
            let projectedInvested = futurePurchases.reduce(0) { $0 + $1.plannedAmount }
            var values = Dictionary(uniqueKeysWithValues: positions.map { ($0.ticker, $0.marketValue) })
            for purchase in futurePurchases {
                values[purchase.ticker, default: 0] += purchase.plannedAmount
            }
            let total = max(1, values.values.reduce(0, +) + max(0, cashBalance - projectedInvested))
            let allocations = values.mapValues { $0 / total }
            let projectedCashNeed = max(0, projectedInvested - cashBalance)
            return ProjectedPlanSnapshot(
                horizonMonths: horizon,
                projectedInvestedAmount: projectedInvested,
                projectedCashNeed: projectedCashNeed,
                projectedAllocations: allocations,
                warnings: purchasePlanWarnings(
                    purchases: futurePurchases,
                    projectedCashNeed: projectedCashNeed,
                    allocations: allocations
                )
            )
        }
    }

    var financialGoalProjection: FinancialGoalProjection {
        let targetValue = portfolioGoal.targetPortfolioValue
        let currentValue = totalMarketValue
        let annualGrowthRate = annualizedTimeWeightedGrowthRate()
        let dividendYield = trailingAnnualDividendYield()
        let effectiveAnnualRate = max(-0.95, annualGrowthRate + dividendYield)
        let plannedContributionTotal = openPlannedPurchases.reduce(0) { $0 + $1.plannedAmount }
        let progress = targetValue <= 0 ? 0 : min(max(currentValue / targetValue, 0), 1)
        let points = goalProjectionPoints(
            startingValue: currentValue,
            targetValue: targetValue,
            annualGrowthRate: annualGrowthRate,
            dividendYield: dividendYield
        )
        let plannedContributionUsed = points.last?.contributions ?? 0
        let contributionGrowth = points.last?.growth ?? 0
        let contributionDividends = points.last.map { max(0, $0.value - currentValue - $0.contributions - $0.growth) } ?? 0

        guard targetValue > 0 else {
            return FinancialGoalProjection(
                status: .notConfigured,
                currentValue: currentValue,
                targetValue: targetValue,
                gap: 0,
                progress: progress,
                annualGrowthRate: annualGrowthRate,
                dividendYield: dividendYield,
                effectiveAnnualRate: effectiveAnnualRate,
                plannedContributionTotal: plannedContributionTotal,
                plannedContributionUsed: plannedContributionUsed,
                contributionGrowth: contributionGrowth,
                contributionDividends: contributionDividends,
                reasonText: "Введите желаемую сумму портфеля.",
                projectedPoints: points,
                projectedDate: nil,
                monthsToGoal: nil
            )
        }

        if currentValue >= targetValue {
            return FinancialGoalProjection(
                status: .achieved,
                currentValue: currentValue,
                targetValue: targetValue,
                gap: 0,
                progress: 1,
                annualGrowthRate: annualGrowthRate,
                dividendYield: dividendYield,
                effectiveAnnualRate: effectiveAnnualRate,
                plannedContributionTotal: plannedContributionTotal,
                plannedContributionUsed: 0,
                contributionGrowth: 0,
                contributionDividends: 0,
                reasonText: "Цель уже достигнута.",
                projectedPoints: [
                    GoalProjectionPoint(month: 0, date: Date().startOfDay, value: currentValue, contributions: 0, growth: 0)
                ],
                projectedDate: Date().startOfDay,
                monthsToGoal: 0
            )
        }

        if let reachedPoint = points.first(where: { $0.month > 0 && $0.value >= targetValue }) {
            return FinancialGoalProjection(
                status: .reachable,
                currentValue: currentValue,
                targetValue: targetValue,
                gap: max(0, targetValue - currentValue),
                progress: progress,
                annualGrowthRate: annualGrowthRate,
                dividendYield: dividendYield,
                effectiveAnnualRate: effectiveAnnualRate,
                plannedContributionTotal: plannedContributionTotal,
                plannedContributionUsed: reachedPoint.contributions,
                contributionGrowth: reachedPoint.growth,
                contributionDividends: max(0, reachedPoint.value - currentValue - reachedPoint.contributions - reachedPoint.growth),
                reasonText: "Прогноз учитывает текущий портфель, исторический рост, дивиденды и открытую очередь покупок.",
                projectedPoints: Array(points.prefix { $0.month <= reachedPoint.month }),
                projectedDate: reachedPoint.date,
                monthsToGoal: reachedPoint.month
            )
        }

        return FinancialGoalProjection(
            status: .unreachable,
            currentValue: currentValue,
            targetValue: targetValue,
            gap: max(0, targetValue - currentValue),
            progress: progress,
            annualGrowthRate: annualGrowthRate,
            dividendYield: dividendYield,
            effectiveAnnualRate: effectiveAnnualRate,
            plannedContributionTotal: plannedContributionTotal,
            plannedContributionUsed: plannedContributionUsed,
            contributionGrowth: contributionGrowth,
            contributionDividends: contributionDividends,
            reasonText: "При текущем темпе и открытой очереди цель не достигается.",
            projectedPoints: points,
            projectedDate: nil,
            monthsToGoal: nil
        )
    }

    var alerts: [PortfolioAlert] {
        var result: [PortfolioAlert] = []

        if let lastRefreshError {
            result.append(PortfolioAlert(
                id: "refresh-error",
                icon: "exclamationmark.triangle.fill",
                title: "Есть ошибка обновления котировок",
                detail: lastRefreshError,
                severity: .warning
            ))
        } else {
            result.append(PortfolioAlert(
                id: "refresh-ok",
                icon: "checkmark.circle.fill",
                title: "Котировки доступны",
                detail: marketDataRefreshedAt.map { "Последнее обновление: \($0.formatted(AppFormatters.compactDate))" } ?? "Локальный кэш готов к работе.",
                severity: .info
            ))
        }

        if let refreshedAt = marketDataRefreshedAt,
           let days = Calendar.current.dateComponents([.day], from: refreshedAt, to: Date()).day,
           days >= 3 {
            result.append(PortfolioAlert(
                id: "stale-quotes",
                icon: "clock.badge.exclamationmark",
                title: "Котировки давно не обновлялись",
                detail: "Последнее успешное обновление было \(days) дн. назад.",
                severity: .warning
            ))
        }

        if cashBalance < 10 {
            result.append(PortfolioAlert(
                id: "low-cash",
                icon: "banknote",
                title: "Низкий свободный кэш",
                detail: cashBalance.formatted(AppFormatters.usd),
                severity: .warning
            ))
        }

        let today = Date().startOfDay
        for purchase in openPlannedPurchases.prefix(5) {
            let days = Calendar.current.dateComponents([.day], from: today, to: purchase.scheduledDate).day ?? 0
            if days < 0 || days <= 14 {
                result.append(PortfolioAlert(
                    id: "plan-\(purchase.id)",
                    icon: days < 0 ? "calendar.badge.exclamationmark" : "calendar.badge.clock",
                    title: days < 0 ? "Плановая покупка просрочена" : "Плановая покупка скоро",
                    detail: "\(purchase.ticker) • \(purchase.plannedAmount.formatted(AppFormatters.usd)) • \(purchase.scheduledDate.formatted(AppFormatters.compactDate))",
                    severity: days < 0 ? .critical : .info
                ))
            }
        }

        return result
    }

    var dataHealthIssues: [DataHealthIssue] {
        var issues: [DataHealthIssue] = []
        if duplicateTransactionKeys().isEmpty == false {
            issues.append(DataHealthIssue(
                id: "duplicate-transactions",
                icon: "doc.on.doc",
                title: "Возможные дубликаты сделок",
                detail: "Найдены операции с одинаковыми датой, типом, тикером, количеством, ценой и суммой.",
                severity: .warning
            ))
        }

        let oversold = oversoldTickers()
        if oversold.isEmpty == false {
            issues.append(DataHealthIssue(
                id: "oversold-positions",
                icon: "minus.circle",
                title: "Продажа больше доступного количества",
                detail: oversold.joined(separator: ", "),
                severity: .critical
            ))
        }

        if cashBalance < 0 {
            issues.append(DataHealthIssue(
                id: "negative-cash",
                icon: "banknote",
                title: "Отрицательный кэш",
                detail: cashBalance.formatted(AppFormatters.usd),
                severity: .critical
            ))
        }

        let emptyTickerCount = transactions.filter { $0.kind.affectsPosition && $0.ticker.normalizedTicker.isEmpty }.count
        if emptyTickerCount > 0 {
            issues.append(DataHealthIssue(
                id: "empty-tickers",
                icon: "text.badge.xmark",
                title: "Есть сделки без тикера",
                detail: "\(emptyTickerCount) операций не попадут в котировки и аналитику.",
                severity: .critical
            ))
        }

        let missingQuotes = positions.filter { $0.currentPrice == nil }.map(\.ticker)
        if !missingQuotes.isEmpty {
            issues.append(DataHealthIssue(
                id: "missing-quotes",
                icon: "chart.line.downtrend.xyaxis",
                title: "Не у всех активов есть котировка",
                detail: missingQuotes.joined(separator: ", "),
                severity: .warning
            ))
        }

        if backupFiles.isEmpty {
            issues.append(DataHealthIssue(
                id: "no-backups",
                icon: "externaldrive.badge.xmark",
                title: "Нет видимых резервных копий",
                detail: "Бэкап появится после следующего сохранения портфеля.",
                severity: .warning
            ))
        }

        if transactions.isEmpty {
            issues.append(DataHealthIssue(
                id: "empty-portfolio",
                icon: "tray",
                title: "Портфель пуст",
                detail: "Добавьте сделки или импортируйте CSV.",
                severity: .info
            ))
        }

        return issues
    }

    func bestCompanyName(for ticker: String) -> String? {
        let symbol = ticker.normalizedTicker
        guard !symbol.isEmpty else { return nil }

        if let cached = companyProfilesByTicker[symbol]?.companyName,
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cached
        }

        return transactions
            .reversed()
            .first { $0.ticker.normalizedTicker == symbol && !$0.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .companyName
    }

    func companyLogoURL(for ticker: String) -> URL? {
        let symbol = ticker.normalizedTicker
        guard !symbol.isEmpty else { return nil }
        return companyProfilesByTicker[symbol]?.logoURL ?? MarketDataAppClient.logoURL(for: symbol)
    }

    func resolveCompanyProfile(for ticker: String) async -> CompanyProfile? {
        let symbol = ticker.normalizedTicker
        guard !symbol.isEmpty else { return nil }

        if let existing = companyProfilesByTicker[symbol] {
            return existing
        }

        if let localName = bestCompanyName(for: symbol) {
            let profile = CompanyProfile(
                ticker: symbol,
                companyName: localName,
                logoURL: MarketDataAppClient.logoURL(for: symbol)
            )
            companyProfilesByTicker[symbol] = profile
            saveMarketDataCache()
            return profile
        }

        do {
            let profile = try await marketData.fetchCompanyProfile(for: symbol)
            companyProfilesByTicker[symbol] = profile
            saveMarketDataCache()
            return profile
        } catch {
            return nil
        }
    }

    func add(_ transaction: InvestmentTransaction) {
        let before = transactions
        transactions.append(transaction)
        transactions.sort { $0.purchaseDate < $1.purchaseDate }
        refreshPortfolioSnapshots()
        save()
        recordJournal(.add, summary: "Добавлена операция \(transaction.kind.title) \(transaction.ticker)", before: before, after: transactions)
    }

    func update(_ transaction: InvestmentTransaction) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        let before = transactions
        transactions[index] = transaction
        transactions.sort { $0.purchaseDate < $1.purchaseDate }
        refreshPortfolioSnapshots()
        save()
        recordJournal(.update, summary: "Изменена операция \(transaction.kind.title) \(transaction.ticker)", before: before, after: transactions)
    }

    func deleteTransactions(withIDs ids: Set<UUID>) {
        let before = transactions
        transactions.removeAll { ids.contains($0.id) }
        refreshPortfolioSnapshots()
        save()
        recordJournal(.delete, summary: "Удалено операций: \(ids.count)", before: before, after: transactions)
    }

    func resetToStatementData() {
        let before = transactions
        transactions = StatementSeedData.transactions
        quotesByTicker = [:]
        priceHistoryByTicker = [:]
        refreshPortfolioSnapshots()
        save()
        recordJournal(.restore, summary: "Восстановлены данные из выписки", before: before, after: transactions)
    }

    func completeOnboarding(currencyCode: String, brokerName: String) {
        setupState = AppSetupState(isCompleted: true, currencyCode: currencyCode, brokerName: brokerName)
        saveSetupState()
    }

    func updatePortfolioGoal(_ goal: PortfolioGoal) {
        portfolioGoal = goal
        savePortfolioGoal()
        recordJournal(.update, entity: "goals", summary: "Обновлены цели портфеля")
    }

    func fetchClose(for ticker: String, on date: Date) async throws -> Double {
        let start = Calendar.current.date(byAdding: .day, value: -10, to: date) ?? date
        let prices = try await marketData.fetchHistoricalPrices(for: ticker, from: start, through: date)
        guard let price = prices.last(where: { $0.date <= date.startOfDay })?.close else {
            throw MarketDataError.noData(ticker.normalizedTicker)
        }
        return price
    }

    func refreshAll() async {
        guard !transactions.isEmpty else { return }
        isRefreshing = true
        lastRefreshError = nil
        defer { isRefreshing = false }

        let tickers = marketDataTickers
        guard !tickers.isEmpty else { return }

        let firstDate = transactions.map(\.purchaseDate).min() ?? Date()
        var newQuotes = quotesByTicker
        var newHistory = priceHistoryByTicker
        var errors: [String] = []

        for ticker in tickers.sorted() {
            do {
                async let quote = marketData.fetchLatestQuote(for: ticker)
                async let history = marketData.fetchHistoricalPrices(for: ticker, from: firstDate, through: Date())
                newQuotes[ticker] = try await quote
                newHistory[ticker] = try await history
                if companyProfilesByTicker[ticker] == nil,
                   let profile = try? await marketData.fetchCompanyProfile(for: ticker) {
                    companyProfilesByTicker[ticker] = profile
                }
            } catch {
                errors.append("\(ticker): \(error.localizedDescription)")
            }
        }

        quotesByTicker = newQuotes
        priceHistoryByTicker = newHistory
        refreshPortfolioSnapshots()
        saveMarketDataCache(refreshedAt: Date())
        lastRefreshError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func exportCSV() throws -> URL {
        let exportURL = exportDirectoryURL
            .appendingPathComponent("portfolio-\(DateHelpers.fileStampFormatter.string(from: Date())).csv")

        try FileManager.default.createDirectory(
            at: exportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var lines = ["date,type,ticker,name,shares,price,commission,cash_amount,notes"]
        for transaction in transactions.sorted(by: { $0.purchaseDate < $1.purchaseDate }) {
            let row = [
                DateHelpers.csvDayFormatter.string(from: transaction.purchaseDate),
                transaction.kind.rawValue,
                transaction.ticker,
                transaction.companyName,
                transaction.shares.formatted(.number.precision(.fractionLength(0...9))),
                transaction.purchasePrice.formatted(.number.precision(.fractionLength(0...6))),
                transaction.commission.formatted(.number.precision(.fractionLength(0...2))),
                (transaction.cashAmount ?? 0).formatted(.number.precision(.fractionLength(0...2))),
                transaction.notes
            ].map(csvEscape)
            lines.append(row.joined(separator: ","))
        }

        try lines.joined(separator: "\n").write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }

    func previewCSVImport(from url: URL) throws -> CSVImportPreview {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(text)
        guard let header = rows.first else {
            return CSVImportPreview(sourceURL: url, transactions: [])
        }

        let keys = Dictionary(uniqueKeysWithValues: header.enumerated().map { (normalizeCSVHeader($0.element), $0.offset) })
        let imported = rows.dropFirst().compactMap { row -> InvestmentTransaction? in
            guard let dateText = field(any: ["date", "time", "trade_date", "transaction_date"], row: row, keys: keys),
                  let date = parseImportDate(dateText),
                  let kind = parseImportKind(row: row, keys: keys)
            else {
                return nil
            }

            let ticker = field(any: ["ticker", "symbol", "instrument", "asset", "security"], row: row, keys: keys) ?? ""
            let shares = parseImportNumber(field(any: ["shares", "quantity", "qty", "units"], row: row, keys: keys)) ?? 0
            let rawPrice = parseImportNumber(field(any: ["price", "average_price", "avg_price", "execution_price"], row: row, keys: keys))
            let cashAmount = parseImportNumber(field(any: ["cash_amount", "amount", "total", "net_amount", "value", "proceeds"], row: row, keys: keys))
            let commission = parseImportNumber(field(any: ["commission", "fee", "fees", "charges"], row: row, keys: keys)) ?? 0
            let price = rawPrice ?? {
                guard kind.affectsPosition, shares != 0, let cashAmount else { return 0 }
                return abs(cashAmount / shares)
            }()

            return InvestmentTransaction(
                kind: kind,
                ticker: ticker,
                companyName: field(any: ["name", "company", "description", "security_name"], row: row, keys: keys) ?? "",
                purchaseDate: date,
                shares: abs(shares),
                purchasePrice: price,
                commission: abs(commission),
                cashAmount: kind.affectsPosition ? nil : cashAmount.map(abs),
                notes: field(any: ["notes", "note", "comment", "memo"], row: row, keys: keys) ?? ""
            )
        }

        return CSVImportPreview(sourceURL: url, transactions: imported)
    }

    func previewImportDraft(from url: URL, mapping: ImportColumnMapping? = nil, presetName: String? = nil) throws -> CSVImportDraft {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(text)
        guard let header = rows.first else {
            return CSVImportDraft(sourceURL: url, headers: [], mapping: mapping ?? ImportColumnMapping(), rows: [])
        }

        let effectiveMapping = mapping ?? ImportColumnMapping.autoDetect(headers: header)
        if let presetName, !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveImportPreset(ImportPreset(name: presetName, mapping: effectiveMapping))
        }

        let headerIndexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
        let draftRows = rows.dropFirst().enumerated().map { offset, row in
            importDraftRow(sourceRowIndex: offset + 2, row: row, mapping: effectiveMapping, headerIndexes: headerIndexes)
        }
        return CSVImportDraft(sourceURL: url, headers: header, mapping: effectiveMapping, rows: draftRows)
    }

    func importPreview(_ preview: CSVImportPreview) {
        let before = transactions
        let existingKeys = Set(transactions.map(transactionKey))
        let incoming = preview.transactions.filter { !existingKeys.contains(transactionKey($0)) }
        transactions.append(contentsOf: incoming)
        transactions.sort { $0.purchaseDate < $1.purchaseDate }
        refreshPortfolioSnapshots()
        save()
        recordJournal(.import, summary: "Импортировано операций: \(incoming.count)", before: before, after: transactions)
    }

    func importDraft(_ draft: CSVImportDraft) {
        let before = transactions
        let existingKeys = Set(transactions.map(transactionKey))
        let incoming = draft.validTransactions.filter { !existingKeys.contains(transactionKey($0)) }
        transactions.append(contentsOf: incoming)
        transactions.sort { $0.purchaseDate < $1.purchaseDate }
        refreshPortfolioSnapshots()
        save()
        recordJournal(.import, summary: "Импортировано операций: \(incoming.count)", before: before, after: transactions)
    }

    func refreshBackupFiles() {
        let directory = backupDirectoryURL
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            backupFiles = []
            return
        }

        backupFiles = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> BackupFile? in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let createdAt = values?.creationDate ?? (attributes?[.creationDate] as? Date) ?? Date.distantPast
                let size = Int64(values?.fileSize ?? 0)
                return BackupFile(url: url, createdAt: createdAt, size: size)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func restoreBackup(_ backup: BackupFile) {
        do {
            let before = transactions
            let data = try Data(contentsOf: backup.url)
            transactions = try JSONCoders.decoder.decode([InvestmentTransaction].self, from: data)
            transactions.sort { $0.purchaseDate < $1.purchaseDate }
            refreshPortfolioSnapshots()
            save()
            refreshBackupFiles()
            recordJournal(.restore, summary: "Восстановлен бэкап \(backup.url.lastPathComponent)", before: before, after: transactions)
        } catch {
            lastRefreshError = "Не удалось восстановить резервную копию: \(error.localizedDescription)"
        }
    }

    func undoLastPortfolioChange() -> Bool {
        guard let entry = changeJournal.first(where: { $0.beforeTransactions != nil }),
              let before = entry.beforeTransactions else {
            return false
        }
        transactions = before
        transactions.sort { $0.purchaseDate < $1.purchaseDate }
        refreshPortfolioSnapshots()
        save()
        recordJournal(.undo, summary: "Откат: \(entry.summary)", before: entry.afterTransactions, after: before)
        return true
    }

    func search(_ query: String) -> [PortfolioSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var results: [PortfolioSearchResult] = []

        for position in positions where position.ticker.lowercased().contains(needle) || position.companyName.lowercased().contains(needle) {
            results.append(PortfolioSearchResult(id: "position-\(position.ticker)", title: "\(position.ticker) \(position.companyName)", subtitle: "Позиция", systemImage: "briefcase", ticker: position.ticker))
        }
        for transaction in transactions where transaction.ticker.lowercased().contains(needle) || transaction.companyName.lowercased().contains(needle) || transaction.notes.lowercased().contains(needle) {
            results.append(PortfolioSearchResult(id: "transaction-\(transaction.id)", title: "\(transaction.ticker) \(transaction.kind.title)", subtitle: transaction.purchaseDate.formatted(AppFormatters.compactDate), systemImage: transaction.kind.systemImage, ticker: transaction.ticker))
        }
        return Array(results.prefix(20))
    }

    func assetAllocation(for position: PortfolioPosition, includingCash: Bool = false) -> Double {
        let total = includingCash ? totalMarketValue : securitiesMarketValue
        return total == 0 ? 0 : position.marketValue / total
    }

    func assetAllocation(for ticker: String, includingCash: Bool = false) -> Double {
        guard let position = positions.first(where: { $0.ticker == ticker.normalizedTicker }) else { return 0 }
        return assetAllocation(for: position, includingCash: includingCash)
    }

    func portfolioChartSeries(for range: PortfolioChartRange) -> [PortfolioChartPoint] {
        guard !history.isEmpty else { return [] }

        let filteredHistory: [PortfolioSnapshot]
        if let cutoff = range.cutoffDate(relativeTo: history.last?.date ?? Date()) {
            let filtered = history.filter { $0.date >= cutoff }
            filteredHistory = filtered.count >= 2 ? filtered : Array(history.suffix(2))
        } else {
            filteredHistory = history
        }

        let transactionEvents = Dictionary(grouping: transactions.filter(\.kind.affectsPosition)) {
            chartDayKey(for: $0.purchaseDate)
        }

        let points = filteredHistory.map { snapshot in
            let events = transactionEvents[chartDayKey(for: snapshot.date)] ?? []
            let tickers = Array(Set(events.map(\.ticker).filter { !$0.isEmpty })).sorted()
            return PortfolioChartPoint(
                date: snapshot.date,
                marketValue: snapshot.marketValue,
                investedAmount: snapshot.investedAmount,
                gainLoss: snapshot.gainLoss,
                gainLossPercent: snapshot.gainLossPercent,
                transactionAmount: events.reduce(0) { $0 + $1.displayAmount },
                transactionTickers: tickers
            )
        }

        return sampledChartPoints(points, range: range)
    }

    func assetDetail(for ticker: String) -> AssetDetailSummary? {
        let symbol = ticker.normalizedTicker
        guard !symbol.isEmpty else { return nil }
        let position = positions.first { $0.ticker == symbol }
        let relatedTransactions = transactions.filter { $0.ticker.normalizedTicker == symbol }.sorted { $0.purchaseDate > $1.purchaseDate }
        guard position != nil || relatedTransactions.isEmpty == false else {
            return nil
        }
        let quote = quotesByTicker[symbol]
        let dividendTransactions = relatedTransactions.filter { $0.kind == .dividend }
        let dividends = dividendTransactions.reduce(0) { $0 + $1.displayAmount }
        let marketValue = position?.marketValue ?? 0
        return AssetDetailSummary(
            ticker: symbol,
            companyName: position?.companyName ?? bestCompanyName(for: symbol) ?? symbol,
            shares: position?.shares ?? 0,
            averageCost: position?.averageCost ?? 0,
            currentPrice: quote?.price ?? position?.currentPrice,
            dayChange: quote?.dayChange,
            dayChangePercent: quote?.dayChangePercent,
            marketValue: marketValue,
            allocation: assetAllocation(for: symbol, includingCash: false),
            gainLoss: position?.gainLoss ?? 0,
            gainLossPercent: position?.gainLossPercent ?? 0,
            realizedGainLoss: position?.realizedGainLoss ?? 0,
            dividends: dividends,
            transactions: relatedTransactions,
            dividendTransactions: dividendTransactions
        )
    }

    func addPlannedPurchase(_ purchase: PlannedPurchase) {
        plannedPurchases.append(purchase)
        plannedPurchases.sort { $0.scheduledDate < $1.scheduledDate }
        savePlannedPurchases()
        recordJournal(.add, entity: "plannedPurchase", summary: "Добавлен план \(purchase.ticker)")
    }

    func updatePlannedPurchase(_ purchase: PlannedPurchase) {
        guard let index = plannedPurchases.firstIndex(where: { $0.id == purchase.id }) else { return }
        plannedPurchases[index] = purchase
        plannedPurchases.sort { $0.scheduledDate < $1.scheduledDate }
        savePlannedPurchases()
        recordJournal(.update, entity: "plannedPurchase", summary: "Изменен план \(purchase.ticker)")
    }

    func setPlannedPurchaseCompleted(_ id: UUID, isCompleted: Bool) {
        guard let index = plannedPurchases.firstIndex(where: { $0.id == id }) else { return }
        plannedPurchases[index].isCompleted = isCompleted
        savePlannedPurchases()
        recordJournal(.update, entity: "plannedPurchase", summary: isCompleted ? "План отмечен выполненным" : "План возвращен в очередь")
    }

    func deletePlannedPurchases(withIDs ids: Set<UUID>) {
        plannedPurchases.removeAll { ids.contains($0.id) }
        savePlannedPurchases()
        recordJournal(.delete, entity: "plannedPurchase", summary: "Удалено планов: \(ids.count)")
    }

    func markPlannedPurchaseCompletedAndAddTransaction(
        _ purchase: PlannedPurchase,
        transaction: InvestmentTransaction
    ) {
        add(transaction)
        setPlannedPurchaseCompleted(purchase.id, isCompleted: true)
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            transactions = try JSONCoders.decoder.decode([InvestmentTransaction].self, from: data)
            if transactions.isEmpty || shouldReplaceDemo(transactions) {
                transactions = StatementSeedData.transactions
                save()
            }
        } catch CocoaError.fileReadNoSuchFile {
            transactions = StatementSeedData.transactions
            save()
        } catch {
            lastRefreshError = "Не удалось загрузить локальный портфель: \(error.localizedDescription)"
        }
    }

    private func loadSetupState() {
        do {
            let data = try Data(contentsOf: setupURL)
            setupState = try JSONCoders.decoder.decode(AppSetupState.self, from: data)
        } catch {
            setupState = AppSetupState()
        }
    }

    private func saveSetupState() {
        saveCodable(setupState, to: setupURL, errorPrefix: "Не удалось сохранить настройку запуска")
    }

    private func loadImportPresets() {
        do {
            let data = try Data(contentsOf: importPresetsURL)
            importPresets = try JSONCoders.decoder.decode([ImportPreset].self, from: data)
        } catch {
            importPresets = []
        }
    }

    private func saveImportPresets() {
        saveCodable(importPresets, to: importPresetsURL, errorPrefix: "Не удалось сохранить пресеты импорта")
    }

    private func saveImportPreset(_ preset: ImportPreset) {
        importPresets.removeAll { $0.name == preset.name }
        importPresets.insert(preset, at: 0)
        saveImportPresets()
    }

    private func loadChangeJournal() {
        do {
            let data = try Data(contentsOf: journalURL)
            changeJournal = try JSONCoders.decoder.decode([ChangeJournalEntry].self, from: data)
        } catch {
            changeJournal = []
        }
    }

    private func saveChangeJournal() {
        saveCodable(Array(changeJournal.prefix(200)), to: journalURL, errorPrefix: "Не удалось сохранить журнал изменений")
    }

    private func loadPortfolioGoal() {
        do {
            let data = try Data(contentsOf: goalsURL)
            portfolioGoal = try JSONCoders.decoder.decode(PortfolioGoal.self, from: data)
        } catch {
            portfolioGoal = PortfolioGoal()
        }
    }

    private func savePortfolioGoal() {
        saveCodable(portfolioGoal, to: goalsURL, errorPrefix: "Не удалось сохранить цели портфеля")
    }

    private func saveCodable<T: Encodable>(_ value: T, to url: URL, errorPrefix: String) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONCoders.encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            lastRefreshError = "\(errorPrefix): \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            backupCurrentFileIfNeeded()
            let data = try JSONCoders.encoder.encode(transactions)
            try data.write(to: fileURL, options: [.atomic])
            refreshBackupFiles()
        } catch {
            lastRefreshError = "Не удалось сохранить локальный портфель: \(error.localizedDescription)"
        }
    }

    private func loadMarketDataCache() {
        let cache = cacheStore.load()
        quotesByTicker = cache.quotesByTicker
        priceHistoryByTicker = cache.priceHistoryByTicker
        companyProfilesByTicker = cache.companyProfilesByTicker
        marketDataRefreshedAt = cache.refreshedAt
    }

    private func refreshPortfolioSnapshots() {
        positions = PortfolioCalculator.positions(from: transactions, quotes: quotesByTicker)
        history = PortfolioCalculator.history(from: transactions, priceHistory: priceHistoryByTicker)
        transactionsNewestFirst = transactions.sorted { $0.purchaseDate > $1.purchaseDate }
    }

    private func saveMarketDataCache(refreshedAt: Date? = nil) {
        let effectiveRefreshDate = refreshedAt ?? marketDataRefreshedAt
        marketDataRefreshedAt = effectiveRefreshDate
        cacheStore.save(MarketDataCache(
            quotesByTicker: quotesByTicker,
            priceHistoryByTicker: priceHistoryByTicker,
            companyProfilesByTicker: companyProfilesByTicker,
            refreshedAt: effectiveRefreshDate
        ))
    }

    private func annualizedTimeWeightedGrowthRate() -> Double {
        let snapshots = history.sorted { $0.date < $1.date }
        guard let first = snapshots.first,
              let last = snapshots.last,
              first.date < last.date
        else { return 0 }

        var compoundedReturn = 1.0
        for (previous, current) in zip(snapshots, snapshots.dropFirst()) where previous.marketValue > 0 {
            let investedFlow = current.investedAmount - previous.investedAmount
            let periodReturn = (current.marketValue - previous.marketValue - investedFlow) / previous.marketValue
            guard periodReturn.isFinite else { continue }
            compoundedReturn *= max(0.0001, 1 + periodReturn)
        }

        let days = max(1, Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1)
        guard compoundedReturn > 0 else { return -0.95 }
        let annualized = pow(compoundedReturn, 365.0 / Double(days)) - 1
        guard annualized.isFinite else { return 0 }
        return min(max(annualized, -0.95), 3.0)
    }

    private func trailingAnnualDividendYield() -> Double {
        let dividends = totalDividendsReceived
        guard dividends > 0 else { return 0 }

        let averageMarketValue = history.isEmpty
            ? max(securitiesMarketValue, 1)
            : max(1, history.reduce(0) { $0 + $1.marketValue } / Double(history.count))
        let firstDividendDate = dividendTransactions.map(\.purchaseDate).min()
        let firstHistoryDate = history.first?.date
        let startDate = minDate(firstDividendDate, firstHistoryDate) ?? Date().startOfDay
        let days = max(1, Calendar.current.dateComponents([.day], from: startDate, to: Date().startOfDay).day ?? 1)
        let annualized = (dividends / averageMarketValue) * (365.0 / Double(days))
        guard annualized.isFinite else { return 0 }
        return min(max(annualized, 0), 0.50)
    }

    private func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return min(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func chartDayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func sampledChartPoints(
        _ points: [PortfolioChartPoint],
        range: PortfolioChartRange
    ) -> [PortfolioChartPoint] {
        let maxPoints: Int
        switch range {
        case .week:
            maxPoints = 16
        case .month:
            maxPoints = 45
        case .sixMonths:
            maxPoints = 80
        case .year:
            maxPoints = 96
        case .all:
            maxPoints = 120
        }

        guard points.count > maxPoints else { return points }

        let step = max(1, Int(ceil(Double(points.count) / Double(maxPoints))))
        var sampled: [PortfolioChartPoint] = []
        var includedDays = Set<String>()

        func include(_ point: PortfolioChartPoint) {
            let key = chartDayKey(for: point.date)
            guard includedDays.insert(key).inserted else { return }
            sampled.append(point)
        }

        for (index, point) in points.enumerated() {
            if index == 0 || index == points.count - 1 || index.isMultiple(of: step) || point.transactionAmount != 0 {
                include(point)
            }
        }

        return sampled.sorted { $0.date < $1.date }
    }

    private func purchasePlanWarnings(
        purchases: [PlannedPurchase],
        projectedCashNeed: Double,
        allocations: [String: Double]
    ) -> [String] {
        var warnings: [String] = []

        if projectedCashNeed > 0.000001 {
            warnings.append("Нужно пополнить кэш на \(projectedCashNeed.formatted(AppFormatters.usd)).")
        }

        let calendar = Calendar.current
        let groupedByTickerAndMonth = Dictionary(grouping: purchases) { purchase in
            let components = calendar.dateComponents([.year, .month], from: purchase.scheduledDate)
            return "\(purchase.ticker)-\(components.year ?? 0)-\(components.month ?? 0)"
        }
        if let repeated = groupedByTickerAndMonth.values.first(where: { $0.count > 1 })?.first {
            warnings.append("Повтор \(repeated.ticker) в одном месяце.")
        }

        if let concentrated = allocations.max(by: { $0.value < $1.value }),
           concentrated.value > 0.25 {
            warnings.append("Доля \(concentrated.key) после покупок выше 25%.")
        }

        return Array(warnings.prefix(2))
    }

    private func goalProjectionPoints(
        startingValue: Double,
        targetValue: Double,
        annualGrowthRate: Double,
        dividendYield: Double,
        maxMonths: Int = 600
    ) -> [GoalProjectionPoint] {
        let calendar = Calendar.current
        let today = Date().startOfDay
        let monthlyGrowthRate = pow(max(0.0001, 1 + annualGrowthRate), 1.0 / 12.0) - 1
        let monthlyDividendRate = pow(max(0.0001, 1 + dividendYield), 1.0 / 12.0) - 1
        let purchases = openPlannedPurchases.sorted { $0.scheduledDate < $1.scheduledDate }
        var purchaseIndex = 0
        var projectedValue = startingValue
        var contributionTotal = 0.0
        var growthTotal = 0.0
        var points = [
            GoalProjectionPoint(
                month: 0,
                date: today,
                value: startingValue,
                contributions: 0,
                growth: 0
            )
        ]

        for month in 1...maxMonths {
            let growthAmount = projectedValue * monthlyGrowthRate
            projectedValue = max(0, projectedValue + growthAmount)
            growthTotal += growthAmount

            let dividendAmount = projectedValue * monthlyDividendRate
            projectedValue = max(0, projectedValue + dividendAmount)

            let monthEnd = calendar.date(byAdding: .month, value: month, to: today) ?? today
            while purchaseIndex < purchases.count,
                  purchases[purchaseIndex].scheduledDate <= monthEnd {
                projectedValue += purchases[purchaseIndex].plannedAmount
                contributionTotal += purchases[purchaseIndex].plannedAmount
                purchaseIndex += 1
            }

            points.append(GoalProjectionPoint(
                month: month,
                date: monthEnd.startOfDay,
                value: projectedValue,
                contributions: contributionTotal,
                growth: growthTotal
            ))

            if projectedValue >= targetValue {
                return points
            }

            if monthlyGrowthRate + monthlyDividendRate <= 0, purchaseIndex >= purchases.count, targetValue > 0 {
                return points
            }
        }

        return points
    }

    private func estimatedDividendIntervalDays(from dividends: [InvestmentTransaction]) -> Int {
        let dates = dividends.map(\.purchaseDate).sorted()
        let intervals = zip(dates, dates.dropFirst()).compactMap { previous, next -> Int? in
            let days = Calendar.current.dateComponents([.day], from: previous, to: next).day ?? 0
            return (30...370).contains(days) ? days : nil
        }.sorted()

        guard !intervals.isEmpty else { return 91 }
        return intervals[intervals.count / 2]
    }

    private func loadPlannedPurchases() {
        do {
            let data = try Data(contentsOf: plannedPurchasesURL)
            plannedPurchases = try JSONCoders.decoder.decode([PlannedPurchase].self, from: data)
            if plannedPurchases.isEmpty {
                plannedPurchases = PurchasePlanSeedData.purchases
                savePlannedPurchases()
            }
        } catch CocoaError.fileReadNoSuchFile {
            plannedPurchases = PurchasePlanSeedData.purchases
            savePlannedPurchases()
        } catch {
            lastRefreshError = "Не удалось загрузить план покупок: \(error.localizedDescription)"
        }
    }

    private func savePlannedPurchases() {
        do {
            try FileManager.default.createDirectory(
                at: plannedPurchasesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONCoders.encoder.encode(plannedPurchases)
            try data.write(to: plannedPurchasesURL, options: [.atomic])
        } catch {
            lastRefreshError = "Не удалось сохранить план покупок: \(error.localizedDescription)"
        }
    }

    private func recordJournal(
        _ action: JournalAction,
        entity: String = "portfolio",
        summary: String,
        before: [InvestmentTransaction]? = nil,
        after: [InvestmentTransaction]? = nil
    ) {
        changeJournal.insert(ChangeJournalEntry(
            action: action,
            entity: entity,
            summary: summary,
            beforeTransactions: before,
            afterTransactions: after
        ), at: 0)
        changeJournal = Array(changeJournal.prefix(200))
        saveChangeJournal()
    }

    private func backupCurrentFileIfNeeded() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("portfolio-\(DateHelpers.fileStampFormatter.string(from: Date())).json")

        do {
            try FileManager.default.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
        } catch {
            lastRefreshError = "Не удалось создать резервную копию: \(error.localizedDescription)"
        }
    }

    private func shouldReplaceDemo(_ transactions: [InvestmentTransaction]) -> Bool {
        transactions.count == 1 && transactions.first?.notes.contains("Демо-позиция") == true
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func transactionKey(_ transaction: InvestmentTransaction) -> String {
        [
            DateHelpers.csvDayFormatter.string(from: transaction.purchaseDate),
            transaction.kind.rawValue,
            transaction.ticker,
            String(format: "%.9f", transaction.shares),
            String(format: "%.6f", transaction.purchasePrice),
            String(format: "%.2f", transaction.commission),
            String(format: "%.2f", transaction.cashAmount ?? 0)
        ].joined(separator: "|")
    }

    private func field(_ key: String, row: [String], keys: [String: Int]) -> String? {
        guard let index = keys[key], row.indices.contains(index) else { return nil }
        return row[index]
    }

    private func field(any candidateKeys: [String], row: [String], keys: [String: Int]) -> String? {
        for key in candidateKeys {
            if let value = field(normalizeCSVHeader(key), row: row, keys: keys),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func importDraftRow(
        sourceRowIndex: Int,
        row: [String],
        mapping: ImportColumnMapping,
        headerIndexes: [String: Int]
    ) -> ImportDraftRow {
        func mapped(_ keyPath: KeyPath<ImportColumnMapping, String?>) -> String? {
            guard let header = mapping[keyPath: keyPath],
                  let index = headerIndexes[header],
                  row.indices.contains(index)
            else { return nil }
            return row[index]
        }

        let kind = parseImportKind(raw: mapped(\.type), sharesText: mapped(\.shares))
        let shares = parseImportNumber(mapped(\.shares)) ?? 0
        let cashAmount = parseImportNumber(mapped(\.cashAmount))
        let rawPrice = parseImportNumber(mapped(\.price))
        let price = rawPrice ?? {
            guard kind?.affectsPosition == true, shares != 0, let cashAmount else { return 0 }
            return abs(cashAmount / shares)
        }()

        return ImportDraftRow(
            sourceRowIndex: sourceRowIndex,
            kind: kind,
            ticker: mapped(\.ticker) ?? "",
            companyName: mapped(\.name) ?? "",
            purchaseDate: mapped(\.date).flatMap(parseImportDate),
            shares: abs(shares),
            price: price,
            commission: abs(parseImportNumber(mapped(\.commission)) ?? 0),
            cashAmount: kind?.affectsPosition == true ? nil : cashAmount.map(abs),
            notes: mapped(\.notes) ?? ""
        )
    }

    private func normalizeCSVHeader(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    private func parseImportDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = DateHelpers.csvDayFormatter.date(from: trimmed) {
            return date
        }

        let formats = ["MM/dd/yyyy", "dd.MM.yyyy", "yyyy/MM/dd", "dd/MM/yyyy", "yyyy-MM-dd HH:mm:ss"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private func parseImportNumber(_ value: String?) -> Double? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "USD", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private func parseImportKind(row: [String], keys: [String: Int]) -> TransactionKind? {
        parseImportKind(
            raw: field(any: ["type", "kind", "action", "side", "transaction_type"], row: row, keys: keys),
            sharesText: field(any: ["shares", "quantity", "qty", "units"], row: row, keys: keys)
        )
    }

    private func parseImportKind(raw: String?, sharesText: String?) -> TransactionKind? {
        if let raw = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
            if let kind = TransactionKind(rawValue: raw) {
                return kind
            }
            if raw.contains("buy") || raw.contains("purchase") || raw.contains("bought") {
                return .buy
            }
            if raw.contains("sell") || raw.contains("sold") {
                return .sell
            }
            if raw.contains("dividend") || raw.contains("div") {
                return .dividend
            }
            if raw.contains("deposit") || raw.contains("cash in") || raw.contains("pay in") {
                return .deposit
            }
            if raw.contains("withdraw") || raw.contains("cash out") {
                return .withdrawal
            }
        }

        if let shares = parseImportNumber(sharesText) {
            return shares < 0 ? .sell : .buy
        }
        return nil
    }

    private func duplicateTransactionKeys() -> Set<String> {
        let keys = transactions.map(transactionKey)
        let grouped = Dictionary(grouping: keys) { $0 }
        return Set(grouped.filter { $0.value.count > 1 }.keys)
    }

    private func oversoldTickers() -> [String] {
        let grouped = Dictionary(grouping: transactions.filter(\.kind.affectsPosition)) { $0.ticker.normalizedTicker }
        return grouped.compactMap { ticker, items -> String? in
            var shares = 0.0
            for transaction in items.sorted(by: { $0.purchaseDate < $1.purchaseDate }) {
                switch transaction.kind {
                case .openingPosition, .buy:
                    shares += transaction.shares
                case .sell:
                    shares -= transaction.shares
                    if shares < -0.0000001 {
                        return ticker
                    }
                case .dividend, .deposit, .withdrawal:
                    break
                }
            }
            return nil
        }
        .sorted()
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if insideQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            insideQuotes = false
                            if next == "," {
                                row.append(field)
                                field = ""
                            } else if next == "\n" {
                                row.append(field)
                                rows.append(row)
                                row = []
                                field = ""
                            } else if next != "\r" {
                                field.append(next)
                            }
                        }
                    } else {
                        insideQuotes = false
                    }
                } else {
                    insideQuotes = true
                }
            } else if character == "," && !insideQuotes {
                row.append(field)
                field = ""
            } else if character == "\n" && !insideQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    nonisolated private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("MyInvest", isDirectory: true)
            .appendingPathComponent("portfolio.json")
    }

    nonisolated private static var defaultCacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("MyInvest", isDirectory: true)
            .appendingPathComponent("market-data-cache.json")
    }

    nonisolated private static var defaultPlannedPurchasesURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("MyInvest", isDirectory: true)
            .appendingPathComponent("purchase-plan.json")
    }

    nonisolated private static var defaultSetupURL: URL {
        applicationSupportFile("setup.json")
    }

    nonisolated private static var defaultImportPresetsURL: URL {
        applicationSupportFile("import-presets.json")
    }

    nonisolated private static var defaultJournalURL: URL {
        applicationSupportFile("change-journal.json")
    }

    nonisolated private static var defaultGoalsURL: URL {
        applicationSupportFile("portfolio-goals.json")
    }

    nonisolated private static func applicationSupportFile(_ filename: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("MyInvest", isDirectory: true)
            .appendingPathComponent(filename)
    }

    private var marketData: MarketDataFetching {
        MarketDataAppClient(cookieHeader: yahooCookieHeader)
    }

    private static let keychainService = "com.myinvest.desktop"
}
