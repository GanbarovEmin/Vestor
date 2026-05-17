import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case portfolio
    case purchaseQueue
    case tradeHistory
    case dividends
    case analytics
    case notifications
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Обзор"
        case .portfolio: "Портфель"
        case .purchaseQueue: "Очередь к покупке"
        case .tradeHistory: "История сделок"
        case .dividends: "Дивиденды"
        case .analytics: "Аналитика"
        case .notifications: "Уведомления"
        case .settings: "Настройки"
        }
    }

    var icon: String {
        switch self {
        case .overview: "house.fill"
        case .portfolio: "briefcase"
        case .purchaseQueue: "calendar.badge.plus"
        case .tradeHistory: "clock"
        case .dividends: "dollarsign.circle"
        case .analytics: "chart.bar.xaxis"
        case .notifications: "bell"
        case .settings: "gearshape"
        }
    }
}

enum PortfolioFilter: String, CaseIterable, Identifiable {
    case main
    case longTermGrowth
    case technology

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: "Мой портфель"
        case .longTermGrowth: "Долгосрочный рост"
        case .technology: "Технологии"
        }
    }

    var color: Color {
        switch self {
        case .main: .blue
        case .longTermGrowth: .indigo
        case .technology: .purple
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: PortfolioStore
    @SceneStorage("selected-section") private var selectedSectionRaw = AppSection.overview.rawValue
    @SceneStorage("selected-portfolio-filter") private var selectedPortfolioFilterRaw = PortfolioFilter.main.rawValue
    @State private var isAddingTransaction = false
    @State private var isAddingPlannedPurchase = false

    private var selectedSection: AppSection {
        get { AppSection(rawValue: selectedSectionRaw) ?? .overview }
        nonmutating set { selectedSectionRaw = newValue.rawValue }
    }

    private var selectedPortfolioFilter: PortfolioFilter {
        get { PortfolioFilter(rawValue: selectedPortfolioFilterRaw) ?? .main }
        nonmutating set { selectedPortfolioFilterRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    VestorBrandIcon(size: 34)
                    Text("Vestor")
                        .font(.headline.weight(.semibold))
                    Text("Мой портфель")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.totalMarketValue.formatted(AppFormatters.usd))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text(store.totalGainLoss.formatted(AppFormatters.usd) + " (" + store.totalGainLossPercent.formatted(AppFormatters.percent) + ")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.totalGainLoss >= 0 ? .green : .red)
                        .monospacedDigit()
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)

                List(selection: Binding(get: {
                    selectedSection
                }, set: { newValue in
                    if let newValue {
                        selectedSection = newValue
                    }
                })) {
                    Section {
                        ForEach([AppSection.overview, .portfolio, .purchaseQueue, .tradeHistory, .dividends, .analytics, .notifications]) { section in
                            Label(section.title, systemImage: section.icon)
                                .tag(section)
                        }
                    }

                    Section("Портфели") {
                        ForEach(PortfolioFilter.allCases) { filter in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(filter.color)
                                    .frame(width: 8, height: 8)
                                Text(filter.title)
                                Spacer()
                                if selectedPortfolioFilter == filter {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPortfolioFilter = filter
                                selectedSection = .portfolio
                            }
                        }

                        Button {
                            selectedSection = .settings
                        } label: {
                            Label("Новый портфель", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                    }

                    Section {
                        Label(AppSection.settings.title, systemImage: AppSection.settings.icon)
                            .tag(AppSection.settings)
                    }
                }
                .listStyle(.sidebar)

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Yahoo Finance")
                        Circle()
                            .fill(store.lastRefreshError == nil ? .green : .orange)
                            .frame(width: 7, height: 7)
                    }
                    .font(.caption.weight(.semibold))

                    HStack {
                        Text("NASDAQ")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("USD")
                    }
                    .font(.caption)

                    if let lastDate = store.quotesByTicker.values.map(\.asOf).max() {
                        Text("Обновлено \(lastDate, format: AppFormatters.compactDate)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 230, max: 260)
            .navigationTitle("Vestor")
        } detail: {
            Group {
                switch selectedSection {
                case .overview:
                    DashboardView(isAddingTransaction: $isAddingTransaction)
                case .portfolio:
                    PortfolioHoldingsView(filter: selectedPortfolioFilter)
                case .purchaseQueue:
                    PurchaseQueueView(isAddingPlannedPurchase: $isAddingPlannedPurchase)
                case .tradeHistory:
                    TransactionsView(isAddingTransaction: $isAddingTransaction)
                case .dividends:
                    DividendsView()
                case .analytics:
                    AnalyticsView()
                case .notifications:
                    NotificationsView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle(selectedSection.title)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Label("Обновить", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing || store.transactions.isEmpty)
                    .help("Обновить текущие и исторические котировки")

                    Button {
                        if selectedSection == .purchaseQueue {
                            isAddingPlannedPurchase = true
                        } else {
                            isAddingTransaction = true
                        }
                    } label: {
                        Label(selectedSection == .purchaseQueue ? "Добавить план" : "Добавить сделку", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    .help(selectedSection == .purchaseQueue ? "Добавить запланированную покупку" : "Добавить покупку акции")
                }
            }
        }
        .sheet(isPresented: $isAddingTransaction) {
            TransactionEditorView()
                .environmentObject(store)
        }
        .sheet(isPresented: $isAddingPlannedPurchase) {
            PlannedPurchaseEditorView()
                .environmentObject(store)
        }
    }
}

private struct VestorBrandIcon: View {
    let size: CGFloat
    private var logoImage: NSImage? {
        if let image = NSImage(named: "VestorLogo") {
            return image
        }

        guard let url = Bundle.main.url(forResource: "VestorLogo", withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let image = logoImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                Image(systemName: "circle.grid.cross")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.teal)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
