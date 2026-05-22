import SwiftUI

enum PortfolioAlertSeverity: Int, Hashable {
    case info
    case warning
    case critical

    var color: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct PortfolioAlert: Identifiable, Hashable {
    var id: String
    var icon: String
    var title: String
    var detail: String
    var severity: PortfolioAlertSeverity
}

struct BackupFile: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var createdAt: Date
    var size: Int64
}

struct DataHealthIssue: Identifiable, Hashable {
    var id: String
    var icon: String
    var title: String
    var detail: String
    var severity: PortfolioAlertSeverity
}
