import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var exportedURL: URL?
    @State private var importPreview: CSVImportPreview?

    var body: some View {
        Form {
            Section("Котировки") {
                LabeledContent("Провайдер", value: "Yahoo Finance chart API")
                Text("Приложение получает дневные цены и историю через публичный endpoint query1.finance.yahoo.com/v8/finance/chart. Провайдер изолирован в сервисе, чтобы позже заменить его на официальный Nasdaq/Data Link или брокерский API.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SecureField("Yahoo Cookie header (опционально)", text: $store.yahooCookieHeader)
                    .textFieldStyle(.roundedBorder)
                Text("Поле хранится в macOS Keychain. Обычно оно пустое: текущий Yahoo chart endpoint работает без ключа.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label("Обновить портфель", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing || store.transactions.isEmpty)
            }

            Section("Локальное хранение") {
                LabeledContent("Файл данных") {
                    Text(store.dataFilePath)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.dataFilePath)])
                } label: {
                    Label("Показать файл данных", systemImage: "folder")
                }

                Button {
                    do {
                        exportedURL = try store.exportCSV()
                    } catch {
                        store.lastRefreshError = "Не удалось экспортировать CSV: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Экспорт CSV", systemImage: "square.and.arrow.up")
                }

                Button {
                    selectCSVForImport()
                } label: {
                    Label("Импорт CSV", systemImage: "tray.and.arrow.down")
                }

                Button(role: .destructive) {
                    store.resetToStatementData()
                    Task { await store.refreshAll() }
                } label: {
                    Label("Вернуть данные из выписки", systemImage: "arrow.counterclockwise")
                }

                if let exportedURL {
                    LabeledContent("Последний экспорт") {
                        Text(exportedURL.path)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if let error = store.lastRefreshError {
                Section("Последняя ошибка") {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .sheet(item: $importPreview) { preview in
            ImportPreviewView(preview: preview) {
                store.importPreview(preview)
                importPreview = nil
                Task { await store.refreshAll() }
            } onCancel: {
                importPreview = nil
            }
        }
    }

    private func selectCSVForImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                importPreview = try store.previewCSVImport(from: url)
            } catch {
                store.lastRefreshError = "Не удалось прочитать CSV: \(error.localizedDescription)"
            }
        }
    }
}

private struct ImportPreviewView: View {
    var preview: CSVImportPreview
    var onImport: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Предпросмотр импорта")
                    .font(.title2.weight(.semibold))
                Text("\(preview.transactions.count) операций из \(preview.sourceURL.lastPathComponent)")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            List(preview.transactions) { transaction in
                HStack {
                    Image(systemName: transaction.kind.systemImage)
                        .foregroundStyle(.secondary)
                    Text(transaction.purchaseDate, format: AppFormatters.compactDate)
                        .frame(width: 120, alignment: .leading)
                    Text(transaction.kind.title)
                        .frame(width: 110, alignment: .leading)
                    Text(transaction.ticker.isEmpty ? "-" : transaction.ticker)
                        .font(.headline)
                        .frame(width: 72, alignment: .leading)
                    Spacer()
                    Text(transaction.displayAmount.formatted(AppFormatters.usd))
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Button("Отмена", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Импортировать", action: onImport)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.transactions.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 720, height: 520)
    }
}
