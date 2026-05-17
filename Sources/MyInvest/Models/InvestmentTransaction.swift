import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case openingPosition
    case buy
    case sell
    case dividend
    case deposit
    case withdrawal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openingPosition: "Начальная позиция"
        case .buy: "Покупка"
        case .sell: "Продажа"
        case .dividend: "Дивиденд"
        case .deposit: "Пополнение"
        case .withdrawal: "Вывод"
        }
    }

    var systemImage: String {
        switch self {
        case .openingPosition: "tray.and.arrow.down"
        case .buy: "plus.circle"
        case .sell: "minus.circle"
        case .dividend: "dollarsign.circle"
        case .deposit: "arrow.down.forward.circle"
        case .withdrawal: "arrow.up.forward.circle"
        }
    }

    var affectsPosition: Bool {
        switch self {
        case .openingPosition, .buy, .sell: true
        case .dividend, .deposit, .withdrawal: false
        }
    }
}

struct InvestmentTransaction: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: TransactionKind
    var ticker: String
    var companyName: String
    var purchaseDate: Date
    var shares: Double
    var purchasePrice: Double
    var commission: Double
    var cashAmount: Double?
    var notes: String

    init(
        id: UUID = UUID(),
        kind: TransactionKind = .buy,
        ticker: String,
        companyName: String,
        purchaseDate: Date,
        shares: Double,
        purchasePrice: Double,
        commission: Double,
        cashAmount: Double? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.ticker = ticker.normalizedTicker
        self.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.purchaseDate = purchaseDate.startOfDay
        self.shares = shares
        self.purchasePrice = purchasePrice
        self.commission = commission
        self.cashAmount = cashAmount
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var investedAmount: Double {
        switch kind {
        case .openingPosition, .buy:
            tradeValue + commission
        case .sell, .dividend, .deposit, .withdrawal:
            0
        }
    }

    var tradeValue: Double {
        switch kind {
        case .buy, .sell:
            cashAmount ?? shares * purchasePrice
        case .openingPosition:
            shares * purchasePrice
        case .dividend, .deposit, .withdrawal:
            cashAmount ?? shares * purchasePrice
        }
    }

    var signedShares: Double {
        switch kind {
        case .openingPosition, .buy:
            shares
        case .sell:
            -shares
        case .dividend, .deposit, .withdrawal:
            0
        }
    }

    var cashImpact: Double {
        switch kind {
        case .openingPosition:
            0
        case .buy:
            -(tradeValue + commission)
        case .sell:
            tradeValue - commission
        case .dividend, .deposit:
            cashAmount ?? tradeValue
        case .withdrawal:
            -(cashAmount ?? tradeValue)
        }
    }

    var displayAmount: Double {
        switch kind {
        case .openingPosition, .buy, .sell:
            tradeValue + commission
        case .dividend, .deposit, .withdrawal:
            abs(cashAmount ?? tradeValue)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case ticker
        case companyName
        case purchaseDate
        case shares
        case purchasePrice
        case commission
        case cashAmount
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(TransactionKind.self, forKey: .kind) ?? .buy
        ticker = (try container.decodeIfPresent(String.self, forKey: .ticker) ?? "").normalizedTicker
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName) ?? ""
        purchaseDate = try container.decode(Date.self, forKey: .purchaseDate).startOfDay
        shares = try container.decodeIfPresent(Double.self, forKey: .shares) ?? 0
        purchasePrice = try container.decodeIfPresent(Double.self, forKey: .purchasePrice) ?? 0
        commission = try container.decodeIfPresent(Double.self, forKey: .commission) ?? 0
        cashAmount = try container.decodeIfPresent(Double.self, forKey: .cashAmount)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

struct DividendPaymentSummary: Identifiable, Hashable {
    var id: String { "\(ticker)-\(expectedDate.timeIntervalSince1970)" }
    var ticker: String
    var companyName: String
    var expectedDate: Date
    var expectedAmount: Double
}

extension String {
    var normalizedTicker: String {
        trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
