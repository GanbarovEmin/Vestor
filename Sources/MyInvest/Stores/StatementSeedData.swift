import Foundation

enum StatementSeedData {
    static let importSignature = "Broker app History through May 15 2026"

    static var transactions: [InvestmentTransaction] {
        [
            cash(.deposit, date: "2025-09-19", amount: 30.00),
            buy("AAPL", "Apple Inc.", date: "2025-09-19", shares: 0.118126272912, price: 245.50, amount: 29.00, commission: 1.00),
            cash(.deposit, date: "2025-10-20", amount: 60.00),
            buy("NVDA", "NVIDIA Corporation", date: "2025-10-20", shares: 0.323039861602, price: 182.639999, amount: 59.00, commission: 1.00),
            cash(.deposit, date: "2025-11-04", amount: 205.00),
            buy("AAPL", "Apple Inc.", date: "2025-11-04", shares: 0.755443612802, price: 270.040009, amount: 204.00, commission: 1.00),
            cash(.dividend, ticker: "AAPL", name: "Apple Inc.", date: "2025-11-14", amount: 0.17, notes: "Executed dividend; canceled dividend rows excluded"),
            cash(.deposit, date: "2025-12-02", amount: 59.00),
            buy("NVDA", "NVIDIA Corporation", date: "2025-12-02", shares: 0.320511395109, price: 181.460007, amount: 58.16, commission: 1.00),
            cash(.dividend, ticker: "NVDA", name: "NVIDIA Corporation", date: "2025-12-27", amount: 0.01),
            cash(.deposit, date: "2026-02-08", amount: 175.00),
            buy("VOO", "Vanguard S&P 500 ETF", date: "2026-02-08", shares: 0.272660334759, price: 638.229980, amount: 174.02, commission: 1.00),
            cash(.dividend, ticker: "AAPL", name: "Apple Inc.", date: "2026-02-13", amount: 0.17),
            cash(.deposit, date: "2026-03-02", amount: 175.00),
            buy("MSFT", "Microsoft Corp.", date: "2026-03-02", shares: 0.436582625114, price: 398.549988, amount: 174.00, commission: 1.00),
            cash(.deposit, date: "2026-04-01", amount: 200.00),
            buy("MSFT", "Microsoft Corp.", date: "2026-04-01", shares: 0.536604650, price: 371.84, amount: 199.53, commission: 1.00),
            cash(.dividend, ticker: "VOO", name: "Vanguard S&P 500 ETF", date: "2026-04-01", amount: 0.36),
            cash(.dividend, ticker: "NVDA", name: "NVIDIA Corporation", date: "2026-04-02", amount: 0.01),
            cash(.deposit, date: "2026-04-20", amount: 1_000.00),
            buy("AAPL", "Apple Inc.", date: "2026-04-20", shares: 1.098917200, price: 273.00, amount: 300.00, commission: 1.00),
            buy("MSFT", "Microsoft Corp.", date: "2026-04-20", shares: 0.718438975, price: 417.57, amount: 300.00, commission: 1.00),
            buy("NVDA", "NVIDIA Corporation", date: "2026-04-20", shares: 1.493369439, price: 200.89, amount: 300.00, commission: 1.00),
            buy("VOO", "Vanguard S&P 500 ETF", date: "2026-04-20", shares: 0.147403397, price: 651.27, amount: 96.00, commission: 1.00),
            cash(.deposit, date: "2026-05-01", amount: 200.00),
            buy("AAPL", "Apple Inc.", date: "2026-05-01", shares: 0.700926349900, price: 283.91, amount: 199.00, commission: 1.00),
            cash(.dividend, ticker: "AAPL", name: "Apple Inc.", date: "2026-05-15", amount: 0.51)
        ]
    }

    private static func buy(_ ticker: String, _ name: String, date: String, shares: Double, price: Double, amount: Double, commission: Double) -> InvestmentTransaction {
        InvestmentTransaction(
            kind: .buy,
            ticker: ticker,
            companyName: name,
            purchaseDate: day(date),
            shares: shares,
            purchasePrice: price,
            commission: commission,
            cashAmount: amount,
            notes: "Imported from \(importSignature); broker row amount excludes $1 commission"
        )
    }

    private static func cash(_ kind: TransactionKind, ticker: String = "", name: String = "", date: String, amount: Double, notes: String = "Imported from broker app History") -> InvestmentTransaction {
        InvestmentTransaction(
            kind: kind,
            ticker: ticker,
            companyName: name,
            purchaseDate: day(date),
            shares: 0,
            purchasePrice: 0,
            commission: 0,
            cashAmount: amount,
            notes: "\(notes). Source: \(importSignature)"
        )
    }

    private static func day(_ value: String) -> Date {
        DateHelpers.csvDayFormatter.date(from: value) ?? Date()
    }
}
