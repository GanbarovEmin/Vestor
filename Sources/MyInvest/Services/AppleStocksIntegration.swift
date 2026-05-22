import AppKit
import Foundation

enum AppleStocksIntegration {
    private static let bundleIdentifier = "com.apple.stocks"

    static var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    @discardableResult
    static func openTicker(_ ticker: String) -> Bool {
        guard isAvailable else { return false }
        let symbol = ticker.normalizedTicker
        guard !symbol.isEmpty,
              let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return false }

        if let appURL = URL(string: "stocks://\(encoded)"),
           NSWorkspace.shared.open(appURL) {
            return true
        }

        guard let webURL = URL(string: "https://stocks.apple.com/symbol/\(encoded)") else {
            return false
        }
        return NSWorkspace.shared.open(webURL)
    }
}
