import Foundation

struct MarketDataCache: Codable {
    var quotesByTicker: [String: MarketQuote] = [:]
    var priceHistoryByTicker: [String: [HistoricalPrice]] = [:]
    var refreshedAt: Date?
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
