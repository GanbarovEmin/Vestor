import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PortfolioStore

    @State private var currencyCode = "USD"
    @State private var brokerName = "Manual / CSV"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Настроим Vestor")
                    .font(.largeTitle.weight(.semibold))
                Text("Локальный инвестиционный центр: валюта, источник импорта и базовые настройки хранения.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Form {
                Section("База") {
                    TextField("Валюта", text: $currencyCode)
                    TextField("Брокер / источник импорта", text: $brokerName)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 20)

            Divider()

            HStack {
                Spacer()
                Button("Начать") {
                    store.completeOnboarding(currencyCode: currencyCode, brokerName: brokerName)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: 410)
    }
}
