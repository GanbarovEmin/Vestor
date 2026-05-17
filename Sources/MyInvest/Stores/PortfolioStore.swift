import Combine
import Foundation

@MainActor
final class PortfolioStore: ObservableObject {
    @Published private(set) var transactions: [InvestmentTransaction] = []
    @Published private(set) var quotesByTicker: [String: MarketQuote] = [:]
    @Published private(set) var priceHistoryByTicker: [String: [HistoricalPrice]] = [:]
    @Published private(set) var plannedPurchases: [PlannedPurchase] = []
    @Published private(set) var positions: [PortfolioPosition] = []
    @Published private(set) var history: [PortfolioSnapshot] = []
    @Published private(set) var transactionsNewestFirst: [InvestmentTransaction] = []
    @Published private(set) var isRefreshing = false
    @Published var lastRefreshError: String?
    @Published var yahooCookieHeader: String {
        didSet {
            KeychainService.save(yahooCookieHeader, service: Self.keychainService, account: "yahooCookieHeader")
        }
    }

    private let fileURL: URL
    private let plannedPurchasesURL: URL
    private let cacheStore: MarketDataCacheStore

    init(
        fileURL: URL = PortfolioStore.defaultFileURL,
        plannedPurchasesURL: URL = PortfolioStore.defaultPlannedPurchasesURL,
        cacheURL: URL = PortfolioStore.defaultCacheURL
    ) {
        self.fileURL = fileURL
        self.plannedPurchasesURL = plannedPurchasesURL
        self.cacheStore = MarketDataCacheStore(fileURL: cacheURL)
        self.yahooCookieHeader = KeychainService.read(service: Self.keychainService, account: "yahooCookieHeader")
        load()
        loadPlannedPurchases()
        loadMarketDataCache()
        refreshPortfolioSnapshots()
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

    var openPlannedPurchases: [PlannedPurchase] {
        plannedPurchases.filter { !$0.isCompleted }.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var completedPlannedPurchases: [PlannedPurchase] {
        plannedPurchases.filter(\.isCompleted).sorted { $0.scheduledDate > $1.scheduledDate }
    }

    var plannedPurchaseTotal: Double {
        openPlannedPurchases.reduce(0) { $0 + $1.plannedAmount }
    }

    var nextPlannedPurchase: PlannedPurchase? {
        openPlannedPurchases.first
    }

    var marketDataTickers: Set<String> {
        Set(
            transactions
                .filter(\.kind.affectsPosition)
                .map(\.ticker.normalizedTicker)
                .filter { !$0.isEmpty }
        )
    }

    func add(_ transaction: InvestmentTransaction) {
        transactions.append(transaction)
        transactions.sort { $0.purchaseDate < $1.purchaseDate }
        refreshPortfolioSnapshots()
        save()
    }

    func deleteTransactions(withIDs ids: Set<UUID>) {
        transactions.removeAll { ids.contains($0.id) }
        refreshPortfolioSnapshots()
        save()
    }

    func resetToStatementData() {
        transactions = StatementSeedData.transactions
        quotesByTicker = [:]
        priceHistoryByTicker = [:]
        refreshPortfolioSnapshots()
        save()
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
            } catch {
                errors.append("\(ticker): \(error.localizedDescription)")
            }
        }

        quotesByTicker = newQuotes
        priceHistoryByTicker = newHistory
        refreshPortfolioSnapshots()
        cacheStore.save(MarketDataCache(
            quotesByTicker: quotesByTicker,
            priceHistoryByTicker: priceHistoryByTicker,
            refreshedAt: Date()
        ))
        lastRefreshError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func exportCSV() throws -> URL {
        let exportURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("Exports", isDirectory: true)
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

        let keys = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element.lowercased(), $0.offset) })
        let imported = rows.dropFirst().compactMap { row -> InvestmentTransaction? in
            guard let dateText = field("date", row: row, keys: keys),
                  let date = DateHelpers.csvDayFormatter.date(from: dateText),
                  let kindText = field("type", row: row, keys: keys),
                  let kind = TransactionKind(rawValue: kindText)
            else {
                return nil
            }

            return InvestmentTransaction(
                kind: kind,
                ticker: field("ticker", row: row, keys: keys) ?? "",
                companyName: field("name", row: row, keys: keys) ?? "",
                purchaseDate: date,
                shares: Double(field("shares", row: row, keys: keys) ?? "") ?? 0,
                purchasePrice: Double(field("price", row: row, keys: keys) ?? "") ?? 0,
                commission: Double(field("commission", row: row, keys: keys) ?? "") ?? 0,
                cashAmount: Double(field("cash_amount", row: row, keys: keys) ?? ""),
                notes: field("notes", row: row, keys: keys) ?? ""
            )
        }

        return CSVImportPreview(sourceURL: url, transactions: imported)
    }

    func importPreview(_ preview: CSVImportPreview) {
        let existingKeys = Set(transactions.map(transactionKey))
        let incoming = preview.transactions.filter { !existingKeys.contains(transactionKey($0)) }
        transactions.append(contentsOf: incoming)
        transactions.sort { $0.purchaseDate < $1.purchaseDate }
        refreshPortfolioSnapshots()
        save()
    }

    func addPlannedPurchase(_ purchase: PlannedPurchase) {
        plannedPurchases.append(purchase)
        plannedPurchases.sort { $0.scheduledDate < $1.scheduledDate }
        savePlannedPurchases()
    }

    func setPlannedPurchaseCompleted(_ id: UUID, isCompleted: Bool) {
        guard let index = plannedPurchases.firstIndex(where: { $0.id == id }) else { return }
        plannedPurchases[index].isCompleted = isCompleted
        savePlannedPurchases()
    }

    func deletePlannedPurchases(withIDs ids: Set<UUID>) {
        plannedPurchases.removeAll { ids.contains($0.id) }
        savePlannedPurchases()
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

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            backupCurrentFileIfNeeded()
            let data = try JSONCoders.encoder.encode(transactions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            lastRefreshError = "Не удалось сохранить локальный портфель: \(error.localizedDescription)"
        }
    }

    private func loadMarketDataCache() {
        let cache = cacheStore.load()
        quotesByTicker = cache.quotesByTicker
        priceHistoryByTicker = cache.priceHistoryByTicker
    }

    private func refreshPortfolioSnapshots() {
        positions = PortfolioCalculator.positions(from: transactions, quotes: quotesByTicker)
        history = PortfolioCalculator.history(from: transactions, priceHistory: priceHistoryByTicker)
        transactionsNewestFirst = transactions.sorted { $0.purchaseDate > $1.purchaseDate }
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

    private var marketData: MarketDataFetching {
        MarketDataAppClient(cookieHeader: yahooCookieHeader)
    }

    private static let keychainService = "com.myinvest.desktop"
}
