import Foundation
import UserNotifications

enum LocalNotificationService {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func schedulePortfolioNotifications(alerts: [PortfolioAlert], nextDividend: DividendPaymentSummary?) async {
        guard await requestAuthorization() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["vestor-alerts", "vestor-dividend"])

        if let alert = alerts.first(where: { $0.severity != .info }) ?? alerts.first {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.detail
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(identifier: "vestor-alerts", content: content, trigger: trigger)
            try? await center.add(request)
        }

        if let nextDividend {
            let content = UNMutableNotificationContent()
            content.title = "Ожидаемый дивиденд \(nextDividend.ticker)"
            content.body = "\(nextDividend.expectedAmount.formatted(AppFormatters.usd)) • \(nextDividend.expectedDate.formatted(AppFormatters.compactDate))"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 8, repeats: false)
            let request = UNNotificationRequest(identifier: "vestor-dividend", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
