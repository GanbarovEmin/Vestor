import Foundation

enum MarketDataError: LocalizedError {
    case invalidURL
    case noData(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Не удалось собрать URL котировок."
        case .noData(let ticker):
            return "Нет рыночных данных для \(ticker)."
        case .badResponse:
            return "Ответ сервиса котировок не удалось обработать."
        }
    }
}

protocol MarketDataFetching {
    func fetchLatestQuote(for ticker: String) async throws -> MarketQuote
    func fetchHistoricalPrices(for ticker: String, from startDate: Date, through endDate: Date) async throws -> [HistoricalPrice]
}

struct MarketDataAppClient: MarketDataFetching {
    var cookieHeader: String = ""

    func fetchLatestQuote(for ticker: String) async throws -> MarketQuote {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        let prices = try await fetchHistoricalPrices(for: ticker, from: start, through: end)
        guard let latest = prices.last else {
            throw MarketDataError.noData(ticker)
        }

        let previous = prices.dropLast().last?.close
        return MarketQuote(
            ticker: ticker.normalizedTicker,
            price: latest.close,
            previousClose: previous,
            asOf: latest.date
        )
    }

    func fetchHistoricalPrices(
        for ticker: String,
        from startDate: Date,
        through endDate: Date
    ) async throws -> [HistoricalPrice] {
        let symbol = ticker.normalizedTicker
        let period1 = Int(startDate.startOfDay.timeIntervalSince1970)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: endDate.startOfDay) ?? endDate
        let period2 = Int(endOfDay.timeIntervalSince1970)

        guard var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)") else {
            throw MarketDataError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "period1", value: String(period1)),
            URLQueryItem(name: "period2", value: String(period2)),
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "events", value: "history"),
            URLQueryItem(name: "includeAdjustedClose", value: "true")
        ]

        guard let url = components.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 Vestor", forHTTPHeaderField: "User-Agent")
        let cookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MarketDataError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MarketDataError.badResponse
        }

        let payload = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        guard payload.chart.error == nil,
              let result = payload.chart.result?.first,
              let timestamps = result.timestamp,
              let closes = result.indicators.quote.first?.close,
              timestamps.count == closes.count
        else {
            throw MarketDataError.badResponse
        }

        let prices = zip(timestamps, closes).compactMap { timestamp, close -> HistoricalPrice? in
            guard let close, close > 0 else { return nil }
            return HistoricalPrice(
                ticker: symbol,
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)).startOfDay,
                close: close
            )
        }

        guard !prices.isEmpty else {
            throw MarketDataError.noData(symbol)
        }

        return prices.sorted { $0.date < $1.date }
    }
}

private struct YahooChartResponse: Decodable {
    var chart: YahooChart
}

private struct YahooChart: Decodable {
    var result: [YahooChartResult]?
    var error: YahooChartError?
}

private struct YahooChartError: Decodable {
    var code: String?
    var description: String?
}

private struct YahooChartResult: Decodable {
    var timestamp: [Int]?
    var indicators: YahooIndicators
}

private struct YahooIndicators: Decodable {
    var quote: [YahooQuote]
}

private struct YahooQuote: Decodable {
    var close: [Double?]
}
