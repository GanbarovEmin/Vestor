import XCTest
@testable import MyInvest

final class PriorityFeaturesTests: XCTestCase {
    @MainActor
    func testImportMappingDraftValidationAndPresetPersistence() throws {
        let urls = temporaryStoreURLs()
        let store = PortfolioStore(
            fileURL: urls.portfolio,
            plannedPurchasesURL: urls.plannedPurchases,
            setupURL: urls.setup,
            importPresetsURL: urls.importPresets,
            journalURL: urls.journal,
            goalsURL: urls.goals,
            cacheURL: urls.cache
        )
        let csvURL = urls.root.appendingPathComponent("mapped.csv")
        try """
        Trade Date,Action,Symbol,Company,Quantity,Trade Price,Fee,Net Amount
        2026-03-01,Buy,AAPL,Apple Inc.,2,150,1,301
        2026-03-02,Sell,AAPL,Apple Inc.,1,160,1,159
        2026-03-03,Buy,,Missing Ticker,1,20,0,20
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let mapping = ImportColumnMapping.autoDetect(headers: [
            "Trade Date", "Action", "Symbol", "Company", "Quantity", "Trade Price", "Fee", "Net Amount"
        ])
        let draft = try store.previewImportDraft(from: csvURL, mapping: mapping, presetName: "Generic Broker")

        XCTAssertEqual(draft.rows.count, 3)
        XCTAssertTrue(draft.rows[0].validationIssues.isEmpty)
        XCTAssertTrue(draft.rows[2].validationIssues.contains(.missingTicker))
        XCTAssertEqual(store.importPresets.first?.name, "Generic Broker")
    }

    @MainActor
    func testJournalAndUndoRestoreTransactionSnapshot() {
        let urls = temporaryStoreURLs()
        let store = PortfolioStore(
            fileURL: urls.portfolio,
            plannedPurchasesURL: urls.plannedPurchases,
            setupURL: urls.setup,
            importPresetsURL: urls.importPresets,
            journalURL: urls.journal,
            goalsURL: urls.goals,
            cacheURL: urls.cache
        )
        store.deleteTransactions(withIDs: Set(store.transactions.map(\.id)))

        store.add(InvestmentTransaction(
            ticker: "AAPL",
            companyName: "Apple Inc.",
            purchaseDate: DateHelpers.csvDayFormatter.date(from: "2026-03-01")!,
            shares: 1,
            purchasePrice: 100,
            commission: 0
        ))

        XCTAssertEqual(store.changeJournal.first?.action, .add)
        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertTrue(store.undoLastPortfolioChange())
        XCTAssertTrue(store.transactions.isEmpty)
    }

    @MainActor
    func testDataHealthFindsDuplicatesOversellsAndNegativeCash() {
        let urls = temporaryStoreURLs()
        let store = PortfolioStore(
            fileURL: urls.portfolio,
            plannedPurchasesURL: urls.plannedPurchases,
            setupURL: urls.setup,
            importPresetsURL: urls.importPresets,
            journalURL: urls.journal,
            goalsURL: urls.goals,
            cacheURL: urls.cache
        )
        store.deleteTransactions(withIDs: Set(store.transactions.map(\.id)))
        let date = DateHelpers.csvDayFormatter.date(from: "2026-03-01")!
        let duplicate = InvestmentTransaction(ticker: "AAPL", companyName: "Apple", purchaseDate: date, shares: 1, purchasePrice: 100, commission: 0)
        store.add(duplicate)
        store.add(duplicate)
        store.add(InvestmentTransaction(kind: .sell, ticker: "MSFT", companyName: "Microsoft", purchaseDate: date, shares: 2, purchasePrice: 50, commission: 0))
        store.add(InvestmentTransaction(kind: .withdrawal, ticker: "", companyName: "", purchaseDate: date, shares: 0, purchasePrice: 0, commission: 0, cashAmount: 10_000))

        let issueIDs = Set(store.dataHealthIssues.map(\.id))
        XCTAssertTrue(issueIDs.contains("duplicate-transactions"))
        XCTAssertTrue(issueIDs.contains("oversold-positions"))
        XCTAssertTrue(issueIDs.contains("negative-cash"))
    }

    @MainActor
    func testGoalsProjectionAnalyticsSummaryAndSearchUseCorePortfolioOnly() {
        let urls = temporaryStoreURLs()
        let store = PortfolioStore(
            fileURL: urls.portfolio,
            plannedPurchasesURL: urls.plannedPurchases,
            setupURL: urls.setup,
            importPresetsURL: urls.importPresets,
            journalURL: urls.journal,
            goalsURL: urls.goals,
            cacheURL: urls.cache
        )
        store.deleteTransactions(withIDs: Set(store.transactions.map(\.id)))
        store.deletePlannedPurchases(withIDs: Set(store.plannedPurchases.map(\.id)))
        let date = DateHelpers.csvDayFormatter.date(from: "2026-01-01")!
        store.add(InvestmentTransaction(kind: .deposit, ticker: "", companyName: "", purchaseDate: date, shares: 0, purchasePrice: 0, commission: 0, cashAmount: 1_000))
        store.add(InvestmentTransaction(kind: .buy, ticker: "AAPL", companyName: "Apple Inc.", purchaseDate: date, shares: 2, purchasePrice: 100, commission: 0))
        store.add(InvestmentTransaction(kind: .dividend, ticker: "AAPL", companyName: "Apple Inc.", purchaseDate: date, shares: 0, purchasePrice: 0, commission: 0, cashAmount: 10))
        store.updatePortfolioGoal(PortfolioGoal(targetPortfolioValue: 1_500))

        XCTAssertEqual(store.performanceSummary.currentValue, 1_010, accuracy: 0.0001)
        XCTAssertEqual(store.performanceSummary.investedAmount, 200, accuracy: 0.0001)
        XCTAssertEqual(store.performanceSummary.dividends, 10, accuracy: 0.0001)
        XCTAssertEqual(store.financialGoalProjection.targetValue, 1_500)
        XCTAssertFalse(store.financialGoalProjection.reasonText.isEmpty)
        XCTAssertFalse(store.financialGoalProjection.projectedPoints.isEmpty)
        XCTAssertEqual(store.projectedPlanSnapshots.map(\.horizonMonths), [6, 12, 24])
        XCTAssertTrue(store.projectedPlanSnapshots.allSatisfy(\.warnings.isEmpty))
        XCTAssertTrue(store.search("apple").contains { $0.title.contains("AAPL") })
        XCTAssertFalse(store.search("voo").contains { $0.id.contains("watchlist") || $0.id.contains("group") })
        XCTAssertEqual(store.assetDetail(for: "AAPL")?.ticker, "AAPL")
        XCTAssertNil(store.assetDetail(for: "VOO"))
    }

    func testPortfolioGoalDecodesLegacyPayloadWithoutTargetValue() throws {
        let data = """
        {
          "targetCashAllocation": 0.12,
          "maxAssetAllocation": 0.40,
          "assetTargets": { "VOO": 0.50 },
          "groupTargets": {}
        }
        """.data(using: .utf8)!

        let goal = try JSONCoders.decoder.decode(PortfolioGoal.self, from: data)

        XCTAssertEqual(goal.targetPortfolioValue, 0)
        XCTAssertEqual(goal, PortfolioGoal())
    }

    func testPrimaryNavigationStartsWithOverviewAndOmitsRemovedSections() {
        XCTAssertEqual(AppSection.defaultSection, .overview)
        XCTAssertEqual(AppSection.primaryNavigation, [
            .overview,
            .goals,
            .purchaseQueue,
            .tradeHistory,
            .dividends,
            .analytics,
            .notifications
        ])
        XCTAssertNil(AppSection(rawValue: "portfolio"))
        XCTAssertNil(AppSection(rawValue: "strategy"))
        XCTAssertNil(AppSection(rawValue: "watchlist"))
    }

    @MainActor
    func testCapitalCompositionExcludesDividendsAsSeparateCapitalSlice() {
        let store = cleanProjectionStore()
        let date = DateHelpers.csvDayFormatter.date(from: "2026-01-01")!
        store.add(InvestmentTransaction(kind: .deposit, ticker: "", companyName: "", purchaseDate: date, shares: 0, purchasePrice: 0, commission: 0, cashAmount: 1_000))
        store.add(InvestmentTransaction(kind: .buy, ticker: "AAPL", companyName: "Apple Inc.", purchaseDate: date, shares: 4, purchasePrice: 100, commission: 0))
        store.add(InvestmentTransaction(kind: .dividend, ticker: "AAPL", companyName: "Apple Inc.", purchaseDate: date, shares: 0, purchasePrice: 0, commission: 0, cashAmount: 10))

        let slices = store.capitalCompositionSlices

        XCTAssertEqual(slices.map(\.title), ["Активы", "Кэш"])
        XCTAssertEqual(slices.first { $0.title == "Активы" }?.value ?? 0, 400, accuracy: 0.0001)
        XCTAssertEqual(slices.first { $0.title == "Кэш" }?.value ?? 0, 610, accuracy: 0.0001)
        XCTAssertFalse(slices.contains { $0.title == "Дивиденды" })
    }

    @MainActor
    func testFinancialGoalProjectionReportsAlreadyReachedTarget() {
        let store = cleanProjectionStore()
        let date = DateHelpers.csvDayFormatter.date(from: "2026-01-01")!
        store.add(InvestmentTransaction(kind: .deposit, ticker: "", companyName: "", purchaseDate: date, shares: 0, purchasePrice: 0, commission: 0, cashAmount: 1_000))
        store.updatePortfolioGoal(PortfolioGoal(targetPortfolioValue: 900))

        let projection = store.financialGoalProjection

        XCTAssertEqual(projection.status, .achieved)
        XCTAssertEqual(projection.currentValue, 1_000, accuracy: 0.0001)
        XCTAssertEqual(projection.gap, 0, accuracy: 0.0001)
        XCTAssertEqual(projection.monthsToGoal, 0)
        XCTAssertEqual(projection.reasonText, "Цель уже достигнута.")
        XCTAssertEqual(projection.projectedPoints.last?.value ?? 0, 1_000, accuracy: 0.0001)
    }

    @MainActor
    func testFinancialGoalProjectionReachesTargetWithPlannedPurchases() {
        let store = cleanProjectionStore()
        let date = DateHelpers.csvDayFormatter.date(from: "2026-01-01")!
        store.add(InvestmentTransaction(kind: .deposit, ticker: "", companyName: "", purchaseDate: date, shares: 0, purchasePrice: 0, commission: 0, cashAmount: 1_000))
        store.addPlannedPurchase(PlannedPurchase(
            scheduledDate: Calendar.current.date(byAdding: .month, value: 1, to: Date())!,
            ticker: "VOO",
            companyName: "Vanguard S&P 500 ETF",
            plannedAmount: 400
        ))
        store.updatePortfolioGoal(PortfolioGoal(targetPortfolioValue: 1_300))

        let projection = store.financialGoalProjection

        XCTAssertEqual(projection.status, .reachable)
        XCTAssertEqual(projection.plannedContributionTotal, 400, accuracy: 0.0001)
        XCTAssertNotNil(projection.projectedDate)
        XCTAssertNotNil(projection.monthsToGoal)
        XCTAssertLessThanOrEqual(projection.monthsToGoal ?? 99, 2)
        XCTAssertGreaterThanOrEqual(projection.projectedPoints.last?.value ?? 0, 1_300)
        XCTAssertEqual(projection.plannedContributionTotal, projection.plannedContributionUsed, accuracy: 0.0001)
        XCTAssertGreaterThan(projection.plannedContributionUsed, 0)
    }

    @MainActor
    func testFinancialGoalProjectionReportsUnreachableWhenNoGrowthOrContributions() {
        let store = cleanProjectionStore()
        let date = DateHelpers.csvDayFormatter.date(from: "2026-01-01")!
        store.add(InvestmentTransaction(kind: .deposit, ticker: "", companyName: "", purchaseDate: date, shares: 0, purchasePrice: 0, commission: 0, cashAmount: 1_000))
        store.updatePortfolioGoal(PortfolioGoal(targetPortfolioValue: 1_100))

        let projection = store.financialGoalProjection

        XCTAssertEqual(projection.status, .unreachable)
        XCTAssertNil(projection.projectedDate)
        XCTAssertNil(projection.monthsToGoal)
        XCTAssertEqual(projection.gap, 100, accuracy: 0.0001)
        XCTAssertEqual(projection.reasonText, "При текущем темпе и открытой очереди цель не достигается.")
    }

    @MainActor
    func testOnboardingPersistsSetupState() {
        let urls = temporaryStoreURLs()
        let store = PortfolioStore(
            fileURL: urls.portfolio,
            plannedPurchasesURL: urls.plannedPurchases,
            setupURL: urls.setup,
            importPresetsURL: urls.importPresets,
            journalURL: urls.journal,
            goalsURL: urls.goals,
            cacheURL: urls.cache
        )

        store.completeOnboarding(currencyCode: "USD", brokerName: "Trading 212")

        XCTAssertTrue(store.setupState.isCompleted)
        XCTAssertEqual(store.setupState.currencyCode, "USD")
        XCTAssertEqual(store.setupState.brokerName, "Trading 212")
    }

    private func temporaryStoreURLs() -> (
        root: URL,
        portfolio: URL,
        plannedPurchases: URL,
        setup: URL,
        importPresets: URL,
        journal: URL,
        goals: URL,
        cache: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("myinvest-priority-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            root: directory,
            portfolio: directory.appendingPathComponent("portfolio.json"),
            plannedPurchases: directory.appendingPathComponent("purchase-plan.json"),
            setup: directory.appendingPathComponent("setup.json"),
            importPresets: directory.appendingPathComponent("import-presets.json"),
            journal: directory.appendingPathComponent("change-journal.json"),
            goals: directory.appendingPathComponent("portfolio-goals.json"),
            cache: directory.appendingPathComponent("market-data-cache.json")
        )
    }

    @MainActor
    private func cleanProjectionStore() -> PortfolioStore {
        let urls = temporaryStoreURLs()
        let store = PortfolioStore(
            fileURL: urls.portfolio,
            plannedPurchasesURL: urls.plannedPurchases,
            setupURL: urls.setup,
            importPresetsURL: urls.importPresets,
            journalURL: urls.journal,
            goalsURL: urls.goals,
            cacheURL: urls.cache
        )
        store.deleteTransactions(withIDs: Set(store.transactions.map(\.id)))
        store.deletePlannedPurchases(withIDs: Set(store.plannedPurchases.map(\.id)))
        return store
    }
}
