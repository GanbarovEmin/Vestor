import Foundation

struct PlannedPurchase: Identifiable, Codable, Hashable {
    var id: UUID
    var scheduledDate: Date
    var ticker: String
    var companyName: String
    var plannedAmount: Double
    var note: String
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        scheduledDate: Date,
        ticker: String,
        companyName: String,
        plannedAmount: Double,
        note: String = "",
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scheduledDate = scheduledDate.startOfDay
        self.ticker = ticker.normalizedTicker
        self.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.plannedAmount = plannedAmount
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
