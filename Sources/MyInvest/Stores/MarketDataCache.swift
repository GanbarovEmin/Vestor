import Foundation

struct MarketDataCache: Codable {
    var quotesByTicker: [String: MarketQuote] = [:]
    var priceHistoryByTicker: [String: [HistoricalPrice]] = [:]
    var companyProfilesByTicker: [String: CompanyProfile] = [:]
    var refreshedAt: Date?

    init(
        quotesByTicker: [String: MarketQuote] = [:],
        priceHistoryByTicker: [String: [HistoricalPrice]] = [:],
        companyProfilesByTicker: [String: CompanyProfile] = [:],
        refreshedAt: Date? = nil
    ) {
        self.quotesByTicker = quotesByTicker
        self.priceHistoryByTicker = priceHistoryByTicker
        self.companyProfilesByTicker = companyProfilesByTicker
        self.refreshedAt = refreshedAt
    }

    enum CodingKeys: String, CodingKey {
        case quotesByTicker
        case priceHistoryByTicker
        case companyProfilesByTicker
        case refreshedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quotesByTicker = try container.decodeIfPresent([String: MarketQuote].self, forKey: .quotesByTicker) ?? [:]
        priceHistoryByTicker = try container.decodeIfPresent([String: [HistoricalPrice]].self, forKey: .priceHistoryByTicker) ?? [:]
        companyProfilesByTicker = try container.decodeIfPresent([String: CompanyProfile].self, forKey: .companyProfilesByTicker) ?? [:]
        refreshedAt = try container.decodeIfPresent(Date.self, forKey: .refreshedAt)
    }
}

struct MarketDataCacheStore {
    var fileURL: URL

    func load() -> MarketDataCache {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONCoders.decoder.decode(MarketDataCache.self, from: data)
        } catch {
            return MarketDataCache()
        }
    }

    func save(_ cache: MarketDataCache) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONCoders.encoder.encode(cache)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Cache persistence should never block portfolio edits.
        }
    }
}
