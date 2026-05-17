import Foundation

struct CSVImportPreview: Identifiable {
    let id = UUID()
    var sourceURL: URL
    var transactions: [InvestmentTransaction]
}
