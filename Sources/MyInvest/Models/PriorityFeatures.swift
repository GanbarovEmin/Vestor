import Foundation

struct AppSetupState: Codable, Hashable {
    var isCompleted: Bool
    var currencyCode: String
    var brokerName: String
    var createdAt: Date

    init(
        isCompleted: Bool = false,
        currencyCode: String = "USD",
        brokerName: String = "",
        createdAt: Date = Date()
    ) {
        self.isCompleted = isCompleted
        self.currencyCode = currencyCode
        self.brokerName = brokerName
        self.createdAt = createdAt
    }
}

struct ImportColumnMapping: Codable, Hashable {
    var date: String?
    var type: String?
    var ticker: String?
    var name: String?
    var shares: String?
    var price: String?
    var commission: String?
    var cashAmount: String?
    var notes: String?

    init(
        date: String? = nil,
        type: String? = nil,
        ticker: String? = nil,
        name: String? = nil,
        shares: String? = nil,
        price: String? = nil,
        commission: String? = nil,
        cashAmount: String? = nil,
        notes: String? = nil
    ) {
        self.date = date
        self.type = type
        self.ticker = ticker
        self.name = name
        self.shares = shares
        self.price = price
        self.commission = commission
        self.cashAmount = cashAmount
        self.notes = notes
    }

    static func autoDetect(headers: [String]) -> ImportColumnMapping {
        func pick(_ candidates: [String]) -> String? {
            headers.first { header in
                let normalized = header.importNormalizedHeader
                return candidates.contains(normalized)
            }
        }

        return ImportColumnMapping(
            date: pick(["date", "time", "trade_date", "transaction_date"]),
            type: pick(["type", "kind", "action", "side", "transaction_type"]),
            ticker: pick(["ticker", "symbol", "instrument", "asset", "security"]),
            name: pick(["name", "company", "description", "security_name"]),
            shares: pick(["shares", "quantity", "qty", "units"]),
            price: pick(["price", "average_price", "avg_price", "execution_price", "trade_price"]),
            commission: pick(["commission", "fee", "fees", "charges"]),
            cashAmount: pick(["cash_amount", "amount", "total", "net_amount", "value", "proceeds"]),
            notes: pick(["notes", "note", "comment", "memo"])
        )
    }
}

struct ImportPreset: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var mapping: ImportColumnMapping
    var createdAt: Date

    init(id: UUID = UUID(), name: String, mapping: ImportColumnMapping, createdAt: Date = Date()) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mapping = mapping
        self.createdAt = createdAt
    }
}

enum ImportValidationIssue: String, Codable, Hashable {
    case missingDate
    case missingKind
    case missingTicker
    case missingShares
    case missingPrice
    case missingAmount
}

struct ImportDraftRow: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceRowIndex: Int
    var isIncluded: Bool
    var kind: TransactionKind?
    var ticker: String
    var companyName: String
    var purchaseDate: Date?
    var shares: Double
    var price: Double
    var commission: Double
    var cashAmount: Double?
    var notes: String

    init(
        id: UUID = UUID(),
        sourceRowIndex: Int,
        isIncluded: Bool = true,
        kind: TransactionKind?,
        ticker: String,
        companyName: String,
        purchaseDate: Date?,
        shares: Double,
        price: Double,
        commission: Double,
        cashAmount: Double?,
        notes: String = ""
    ) {
        self.id = id
        self.sourceRowIndex = sourceRowIndex
        self.isIncluded = isIncluded
        self.kind = kind
        self.ticker = ticker.normalizedTicker
        self.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.purchaseDate = purchaseDate?.startOfDay
        self.shares = shares
        self.price = price
        self.commission = commission
        self.cashAmount = cashAmount
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var validationIssues: [ImportValidationIssue] {
        var issues: [ImportValidationIssue] = []
        if purchaseDate == nil { issues.append(.missingDate) }
        guard let kind else {
            issues.append(.missingKind)
            return issues
        }
        if kind.affectsPosition {
            if ticker.isEmpty { issues.append(.missingTicker) }
            if shares <= 0 { issues.append(.missingShares) }
            if price <= 0 { issues.append(.missingPrice) }
        } else if (cashAmount ?? 0) <= 0 {
            issues.append(.missingAmount)
        }
        return issues
    }

    var transaction: InvestmentTransaction? {
        guard isIncluded, validationIssues.isEmpty, let kind, let purchaseDate else { return nil }
        return InvestmentTransaction(
            kind: kind,
            ticker: ticker,
            companyName: companyName,
            purchaseDate: purchaseDate,
            shares: shares,
            purchasePrice: price,
            commission: commission,
            cashAmount: cashAmount,
            notes: notes
        )
    }
}

struct CSVImportDraft: Identifiable, Hashable {
    let id = UUID()
    var sourceURL: URL
    var headers: [String]
    var mapping: ImportColumnMapping
    var rows: [ImportDraftRow]

    var validTransactions: [InvestmentTransaction] {
        rows.compactMap(\.transaction)
    }
}

enum JournalAction: String, Codable, Hashable {
    case add
    case update
    case delete
    case `import`
    case restore
    case undo
}

struct ChangeJournalEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var action: JournalAction
    var entity: String
    var summary: String
    var beforeTransactions: [InvestmentTransaction]?
    var afterTransactions: [InvestmentTransaction]?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        action: JournalAction,
        entity: String = "portfolio",
        summary: String,
        beforeTransactions: [InvestmentTransaction]? = nil,
        afterTransactions: [InvestmentTransaction]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.action = action
        self.entity = entity
        self.summary = summary
        self.beforeTransactions = beforeTransactions
        self.afterTransactions = afterTransactions
    }
}

struct PortfolioGoal: Codable, Hashable {
    var targetPortfolioValue: Double

    init(
        targetPortfolioValue: Double = 0
    ) {
        self.targetPortfolioValue = max(0, targetPortfolioValue)
    }

    enum CodingKeys: String, CodingKey {
        case targetPortfolioValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            targetPortfolioValue: try container.decodeIfPresent(Double.self, forKey: .targetPortfolioValue) ?? 0
        )
    }
}

struct PortfolioPerformanceSummary: Hashable {
    var currentValue: Double
    var investedAmount: Double
    var unrealizedGainLoss: Double
    var realizedGainLoss: Double
    var dividends: Double
    var cash: Double
    var gainLossPercent: Double
}

struct ProjectedPlanSnapshot: Identifiable, Hashable {
    var id: Int { horizonMonths }
    var horizonMonths: Int
    var projectedInvestedAmount: Double
    var projectedCashNeed: Double
    var projectedAllocations: [String: Double]
    var warnings: [String]
}

enum FinancialGoalProjectionStatus: String, Hashable {
    case notConfigured
    case achieved
    case reachable
    case unreachable
}

struct GoalProjectionPoint: Identifiable, Hashable {
    var id: Int { month }
    var month: Int
    var date: Date
    var value: Double
    var contributions: Double
    var growth: Double
}

struct FinancialGoalProjection: Hashable {
    var status: FinancialGoalProjectionStatus
    var currentValue: Double
    var targetValue: Double
    var gap: Double
    var progress: Double
    var annualGrowthRate: Double
    var dividendYield: Double
    var effectiveAnnualRate: Double
    var plannedContributionTotal: Double
    var plannedContributionUsed: Double
    var contributionGrowth: Double
    var contributionDividends: Double
    var reasonText: String
    var projectedPoints: [GoalProjectionPoint]
    var projectedDate: Date?
    var monthsToGoal: Int?
}

struct CapitalCompositionSlice: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var value: Double
    var share: Double
}

struct PortfolioSearchResult: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var ticker: String?
}

struct AssetDetailSummary: Hashable {
    var ticker: String
    var companyName: String
    var currentPrice: Double?
    var dayChange: Double?
    var marketValue: Double
    var allocation: Double
    var gainLoss: Double
    var dividends: Double
    var transactions: [InvestmentTransaction]
}

extension String {
    var importNormalizedHeader: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
