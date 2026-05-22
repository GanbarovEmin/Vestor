import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: PortfolioStore
    @EnvironmentObject private var softwareUpdates: SoftwareUpdateController

    var body: some View {
        Form {
            Section("Обновления") {
                LabeledContent("Канал", value: "GitHub Releases")
                Text("Приложение проверяет appcast на GitHub Pages и предлагает новую версию, когда опубликован свежий DMG.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    softwareUpdates.checkForUpdates()
                } label: {
                    Label("Проверить обновления", systemImage: "arrow.down.circle")
                }
                .disabled(!softwareUpdates.canCheckForUpdates)
            }

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
                Button(role: .destructive) {
                    store.resetToStatementData()
                    Task { await store.refreshAll() }
                } label: {
                    Label("Вернуть данные из выписки", systemImage: "arrow.counterclockwise")
                }

                Text("Импорт и экспорт CSV теперь находятся в разделе «История сделок».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Резервные копии") {
                HStack {
                    Button {
                        store.refreshBackupFiles()
                    } label: {
                        Label("Обновить список", systemImage: "arrow.clockwise")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([store.backupDirectoryURL])
                    } label: {
                        Label("Показать папку", systemImage: "folder")
                    }
                }

                if store.backupFiles.isEmpty {
                    Text("Бэкапы появятся здесь после сохранения портфеля.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.backupFiles.prefix(8)) { backup in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.url.lastPathComponent)
                                    .lineLimit(1)
                                Text("\(backup.createdAt.formatted(AppFormatters.compactDate)) • \(backup.size / 1024) KB")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                store.restoreBackup(backup)
                                Task { await store.refreshAll() }
                            } label: {
                                Label("Восстановить", systemImage: "arrow.counterclockwise")
                            }
                        }
                    }
                }
            }

            Section("Журнал изменений") {
                Button {
                    _ = store.undoLastPortfolioChange()
                } label: {
                    Label("Откатить последнее изменение портфеля", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.changeJournal.contains { $0.beforeTransactions != nil })

                ForEach(store.changeJournal.prefix(8)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.summary)
                            .font(.callout.weight(.semibold))
                        Text("\(entry.action.rawValue) • \(entry.entity) • \(entry.createdAt.formatted(AppFormatters.compactDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
    }
}
