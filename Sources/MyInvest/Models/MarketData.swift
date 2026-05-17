import Foundation

struct MarketQuote: Codable, Hashable {
    var ticker: String
    var price: Double
    var previousClose: Double?
    var asOf: Date

    var dayChange: Double? {
        guard let previousClose else { return nil }
        return price - previousClose
    }

    var dayChangePercent: Double? {
        guard let previousClose, previousClose != 0 else { return nil }
        return (price - previousClose) / previousClose
    }
}

struct HistoricalPrice: Identifiable, Codable, Hashable {
    var id: String { "\(ticker)-\(date.timeIntervalSince1970)" }
    var ticker: String
    var date: Date
    var close: Double
}

struct CompanyProfile: Codable, Hashable {
    var ticker: String
    var companyName: String
    var logoURL: URL?
}

struct PortfolioPosition: Identifiable, Hashable {
    var id: String { ticker }
    var ticker: String
    var companyName: String
    var shares: Double
    var costBasis: Double
    var averageCost: Double
    var currentPrice: Double?
    var marketValue: Double
    var gainLoss: Double
    var gainLossPercent: Double
    var realizedGainLoss: Double

    var hasLivePrice: Bool {
        currentPrice != nil
    }
}

struct PortfolioSnapshot: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var marketValue: Double
    var investedAmount: Double
    var gainLoss: Double
    var gainLossPercent: Double
}
