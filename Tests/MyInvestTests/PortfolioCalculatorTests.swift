import XCTest
@testable import MyInvest

final class PortfolioCalculatorTests: XCTestCase {
    func testPositionsAggregateTransactionsAndQuotes() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let transactions = [
            InvestmentTransaction(ticker: "aapl", companyName: "Apple", purchaseDate: date, shares: 2, purchasePrice: 100, commission: 1),
            InvestmentTransaction(ticker: "AAPL", companyName: "Apple", purchaseDate: date, shares: 3, purchasePrice: 120, commission: 2)
        ]
        let quotes = [
            "AAPL": MarketQuote(ticker: "AAPL", price: 150, previousClose: 148, asOf: date)
        ]

        let positions = PortfolioCalculator.positions(from: transactions, quotes: quotes)

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0].shares, 5)
        XCTAssertEqual(positions[0].costBasis, 563)
        XCTAssertEqual(positions[0].marketValue, 750)
        XCTAssertEqual(positions[0].gainLoss, 187)
    }

    func testHistoryUsesPurchaseFallbackWhenMarketHistoryIsMissing() {
        let date = DateHelpers.csvDayFormatter.date(from: "2026-01-10")!
        let transactions = [
            InvestmentTransaction(ticker: "MSFT", companyName: "Microsoft", purchaseDate: date, shares: 2, purchasePrice: 50, commission: 0)
        ]

        let history = PortfolioCalculator.history(from: transactions, priceHistory: [:], through: date)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].marketValue, 100)
        XCTAssertEqual(history[0].investedAmount, 100)
    }

    func testSellReducesOpenCostBasisAndTracksRealizedGain() {
        let date = DateHelpers.csvDayFormatter.date(from: "2026-01-10")!
        let transactions = [
            InvestmentTransaction(kind: .buy, ticker: "AAPL", companyName: "Apple", purchaseDate: date, shares: 10, purchasePrice: 100, commission: 0),
            InvestmentTransaction(kind: .sell, ticker: "AAPL", companyName: "Apple", purchaseDate: date, shares: 4, purchasePrice: 130, commission: 1)
        ]

        let positions = PortfolioCalculator.positions(from: transactions, quotes: ["AAPL": MarketQuote(ticker: "AAPL", price: 140, previousClose: 139, asOf: date)])

        XCTAssertEqual(positions[0].shares, 6)
        XCTAssertEqual(positions[0].costBasis, 600)
        XCTAssertEqual(positions[0].realizedGainLoss, 119)
        XCTAssertEqual(positions[0].gainLoss, 240)
    }

    func testStatementSeedMatchesBrokerHistoryHoldingsAndCash() {
        let positions = PortfolioCalculator.positions(from: StatementSeedData.transactions, quotes: [:])
        let byTicker = Dictionary(uniqueKeysWithValues: positions.map { ($0.ticker, $0) })
        let cash = StatementSeedData.transactions.reduce(0) { $0 + $1.cashImpact }

        XCTAssertEqual(byTicker["AAPL"]?.shares ?? 0, 2.673413435614, accuracy: 0.000000001)
        XCTAssertEqual(byTicker["MSFT"]?.shares ?? 0, 1.691626250114, accuracy: 0.000000001)
        XCTAssertEqual(byTicker["NVDA"]?.shares ?? 0, 2.136920695711, accuracy: 0.000000001)
        XCTAssertEqual(byTicker["VOO"]?.shares ?? 0, 0.420063731759, accuracy: 0.000000001)
        XCTAssertEqual(cash, 0.52, accuracy: 0.0000001)
    }

    @MainActor
    func testMarketRefreshTickersIgnoreCashRows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("myinvest-tests-\(UUID().uuidString)")
            .appendingPathComponent("portfolio.json")
        let store = PortfolioStore(fileURL: url, cacheURL: url.deletingLastPathComponent().appendingPathComponent("cache.json"))
        store.resetToStatementData()

        XCTAssertEqual(store.marketDataTickers, ["AAPL", "MSFT", "NVDA", "VOO"])
        XCTAssertFalse(store.marketDataTickers.contains(""))
    }

    func testTransactionKindTitlesAreLocalized() {
        XCTAssertEqual(TransactionKind.buy.title, "Покупка")
        XCTAssertEqual(TransactionKind.deposit.title, "Пополнение")
        XCTAssertEqual(TransactionKind.openingPosition.title, "Начальная позиция")
    }

    func testPurchasePlanSeedMatchesFirstYearPlan() {
        let purchases = PurchasePlanSeedData.purchases
        let total = purchases.reduce(0) { $0 + $1.plannedAmount }

        XCTAssertEqual(purchases.count, 16)
        XCTAssertEqual(total, 6_800)
        XCTAssertEqual(purchases.first?.ticker, "QQQ")
        XCTAssertEqual(purchases.last?.ticker, "NVDA")
        XCTAssertEqual(purchases.filter { $0.note == "Бонус" }.count, 4)
    }

    @MainActor
    func testStoreMaintainsCachedSnapshotsAfterTransactionChanges() {
        let urls = temporaryStoreURLs()
        let store = PortfolioStore(fileURL: urls.portfolio, plannedPurchasesURL: urls.plannedPurchases, cacheURL: urls.cache)
        store.deleteTransactions(withIDs: Set(store.transactions.map(\.id)))

        let older = InvestmentTransaction(
            ticker: "MSFT",
            companyName: "Microsoft",
            purchaseDate: DateHelpers.csvDayFormatter.date(from: "2026-01-10")!,
            shares: 1,
            purchasePrice: 100,
            commission: 0
        )
        let newer = InvestmentTransaction(
            ticker: "AAPL",
            companyName: "Apple",
            purchaseDate: DateHelpers.csvDayFormatter.date(from: "2026-01-15")!,
            shares: 2,
            purchasePrice: 50,
            commission: 0
        )

        store.add(newer)
        store.add(older)

        XCTAssertEqual(store.positions.map(\.ticker).sorted(), ["AAPL", "MSFT"])
        XCTAssertEqual(store.transactionsNewestFirst.map(\.ticker), ["AAPL", "MSFT"])
        XCTAssertEqual(store.history.last?.marketValue, 200)

        store.deleteTransactions(withIDs: [newer.id])

        XCTAssertEqual(store.positions.map(\.ticker), ["MSFT"])
        XCTAssertEqual(store.transactionsNewestFirst.map(\.ticker), ["MSFT"])
        XCTAssertEqual(store.history.last?.marketValue, 100)
    }

    @MainActor
    func testPlannedPurchaseWorkflowSortsCompletesAndDeletes() {
        let urls = temporaryStoreURLs()
        let store = PortfolioStore(fileURL: urls.portfolio, plannedPurchasesURL: urls.plannedPurchases, cacheURL: urls.cache)
        store.deletePlannedPurchases(withIDs: Set(store.plannedPurchases.map(\.id)))

        let second = PlannedPurchase(
            scheduledDate: DateHelpers.csvDayFormatter.date(from: "2026-03-01")!,
            ticker: "VOO",
            companyName: "Vanguard S&P 500 ETF",
            plannedAmount: 400
        )
        let first = PlannedPurchase(
            scheduledDate: DateHelpers.csvDayFormatter.date(from: "2026-02-01")!,
            ticker: "QQQ",
            companyName: "Invesco QQQ",
            plannedAmount: 300
        )

        store.addPlannedPurchase(second)
        store.addPlannedPurchase(first)

        XCTAssertEqual(store.openPlannedPurchases.map(\.ticker), ["QQQ", "VOO"])
        XCTAssertEqual(store.nextPlannedPurchase?.ticker, "QQQ")
        XCTAssertEqual(store.plannedPurchaseTotal, 700)

        store.setPlannedPurchaseCompleted(first.id, isCompleted: true)

        XCTAssertEqual(store.openPlannedPurchases.map(\.ticker), ["VOO"])
        XCTAssertEqual(store.completedPlannedPurchases.map(\.ticker), ["QQQ"])

        store.deletePlannedPurchases(withIDs: [first.id, second.id])

        XCTAssertTrue(store.openPlannedPurchases.isEmpty)
        XCTAssertTrue(store.completedPlannedPurchases.isEmpty)
    }

    private func temporaryStoreURLs() -> (portfolio: URL, plannedPurchases: URL, cache: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("myinvest-tests-\(UUID().uuidString)", isDirectory: true)
        return (
            portfolio: directory.appendingPathComponent("portfolio.json"),
            plannedPurchases: directory.appendingPathComponent("purchase-plan.json"),
            cache: directory.appendingPathComponent("market-data-cache.json")
        )
    }
}
