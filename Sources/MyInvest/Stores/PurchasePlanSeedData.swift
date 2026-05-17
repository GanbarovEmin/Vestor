import Foundation

enum PurchasePlanSeedData {
    static var purchases: [PlannedPurchase] {
        [
            plan("2026-06-01", "QQQ", "Invesco QQQ Trust", 400),
            plan("2026-06-01", "QQQ", "Invesco QQQ Trust", 500, note: "Бонус"),
            plan("2026-07-01", "NFLX", "Netflix Inc.", 400),
            plan("2026-08-01", "AVGO", "Broadcom Inc.", 400),
            plan("2026-09-01", "VOO", "Vanguard S&P 500 ETF", 400),
            plan("2026-09-01", "VOO", "Vanguard S&P 500 ETF", 500, note: "Бонус"),
            plan("2026-10-01", "NVDA", "NVIDIA Corporation", 400),
            plan("2026-11-01", "PLTR", "Palantir Technologies Inc.", 400),
            plan("2026-12-01", "QQQ", "Invesco QQQ Trust", 400),
            plan("2026-12-01", "NVDA", "NVIDIA Corporation", 500, note: "Бонус"),
            plan("2027-01-01", "NFLX", "Netflix Inc.", 400),
            plan("2027-02-01", "MSFT", "Microsoft Corp.", 400),
            plan("2027-03-01", "AVGO", "Broadcom Inc.", 400),
            plan("2027-03-01", "AVGO", "Broadcom Inc.", 500, note: "Бонус"),
            plan("2027-04-01", "AAPL", "Apple Inc.", 400),
            plan("2027-05-01", "NVDA", "NVIDIA Corporation", 400)
        ]
    }

    private static func plan(_ date: String, _ ticker: String, _ name: String, _ amount: Double, note: String = "") -> PlannedPurchase {
        PlannedPurchase(
            scheduledDate: DateHelpers.csvDayFormatter.date(from: date) ?? Date(),
            ticker: ticker,
            companyName: name,
            plannedAmount: amount,
            note: note
        )
    }
}
