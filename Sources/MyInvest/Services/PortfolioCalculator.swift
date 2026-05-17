import Foundation

enum PortfolioCalculator {
    static func positions(
        from transactions: [InvestmentTransaction],
        quotes: [String: MarketQuote]
    ) -> [PortfolioPosition] {
        let grouped = Dictionary(grouping: transactions.filter(\.kind.affectsPosition)) { $0.ticker.normalizedTicker }

        return grouped.map { ticker, transactions in
            let basis = positionBasis(from: transactions)
            let shares = basis.shares
            let costBasis = basis.costBasis
            let averageCost = shares == 0 ? 0 : costBasis / shares
            let currentPrice = quotes[ticker]?.price
            let marketValue = shares * (currentPrice ?? averageCost)
            let gainLoss = marketValue - costBasis
            let gainLossPercent = costBasis == 0 ? 0 : gainLoss / costBasis
            let preferredName = transactions.last(where: { !$0.companyName.isEmpty })?.companyName ?? ticker

            return PortfolioPosition(
                ticker: ticker,
                companyName: preferredName,
                shares: shares,
                costBasis: costBasis,
                averageCost: averageCost,
                currentPrice: currentPrice,
                marketValue: marketValue,
                gainLoss: gainLoss,
                gainLossPercent: gainLossPercent,
                realizedGainLoss: basis.realizedGainLoss
            )
        }
        .filter { abs($0.shares) > 0.0000001 }
        .sorted { $0.marketValue > $1.marketValue }
    }

    static func history(
        from transactions: [InvestmentTransaction],
        priceHistory: [String: [HistoricalPrice]],
        through endDate: Date = Date()
    ) -> [PortfolioSnapshot] {
        guard let firstDate = transactions.map(\.purchaseDate).min() else { return [] }

        let sortedTransactions = transactions.sorted { $0.purchaseDate < $1.purchaseDate }
        let normalizedHistory = priceHistory.mapValues { prices in
            prices.sorted { $0.date < $1.date }
        }

        return DateHelpers.days(from: firstDate, through: endDate).compactMap { date in
            let activeTransactions = sortedTransactions.filter { $0.purchaseDate <= date }
            guard !activeTransactions.isEmpty else { return nil }

            let investedAmount = Dictionary(grouping: activeTransactions.filter(\.kind.affectsPosition)) { $0.ticker.normalizedTicker }
                .values
                .reduce(0) { $0 + positionBasis(from: Array($1)).costBasis }
            let sharesByTicker = Dictionary(grouping: activeTransactions.filter(\.kind.affectsPosition)) { $0.ticker.normalizedTicker }
                .mapValues { positionBasis(from: $0).shares }

            let marketValue = sharesByTicker.reduce(0) { partial, item in
                let ticker = item.key
                let shares = item.value
                guard abs(shares) > 0.0000001 else { return partial }
                let fallbackPrice = fallbackPurchasePrice(for: ticker, date: date, transactions: activeTransactions)
                let close = closePrice(onOrBefore: date, in: normalizedHistory[ticker]) ?? fallbackPrice
                return partial + shares * close
            }

            let gainLoss = marketValue - investedAmount
            let gainLossPercent = investedAmount == 0 ? 0 : gainLoss / investedAmount

            return PortfolioSnapshot(
                date: date,
                marketValue: marketValue,
                investedAmount: investedAmount,
                gainLoss: gainLoss,
                gainLossPercent: gainLossPercent
            )
        }
    }

    private static func closePrice(onOrBefore date: Date, in prices: [HistoricalPrice]?) -> Double? {
        prices?.last(where: { $0.date <= date })?.close
    }

    private static func fallbackPurchasePrice(
        for ticker: String,
        date: Date,
        transactions: [InvestmentTransaction]
    ) -> Double {
        let relevant = transactions.filter { $0.kind.affectsPosition && $0.ticker == ticker && $0.purchaseDate <= date }
        let basis = positionBasis(from: relevant)
        let shares = basis.shares
        guard shares != 0 else { return 0 }
        return basis.costBasis / shares
    }

    private static func positionBasis(from transactions: [InvestmentTransaction]) -> (shares: Double, costBasis: Double, realizedGainLoss: Double) {
        var shares = 0.0
        var costBasis = 0.0
        var realizedGainLoss = 0.0

        for transaction in transactions.sorted(by: { $0.purchaseDate < $1.purchaseDate }) {
            switch transaction.kind {
            case .openingPosition, .buy:
                shares += transaction.shares
                costBasis += transaction.tradeValue + transaction.commission
            case .sell:
                let soldShares = min(transaction.shares, max(shares, 0))
                let averageCost = shares == 0 ? 0 : costBasis / shares
                let removedBasis = averageCost * soldShares
                shares -= soldShares
                costBasis -= removedBasis
                realizedGainLoss += transaction.tradeValue - transaction.commission - removedBasis
            case .dividend, .deposit, .withdrawal:
                break
            }
        }

        if abs(shares) < 0.0000001 {
            shares = 0
            costBasis = 0
        }

        return (shares, costBasis, realizedGainLoss)
    }
}
