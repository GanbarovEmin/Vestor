import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case goals
    case purchaseQueue
    case tradeHistory
    case dividends
    case analytics
    case notifications
    case settings

    var id: String { rawValue }

    static let defaultSection: AppSection = .overview

    static let primaryNavigation: [AppSection] = [
        .overview,
        .goals,
        .purchaseQueue,
        .tradeHistory,
        .dividends,
        .analytics,
        .notifications
    ]

    var title: String {
        switch self {
        case .overview: "Обзор"
        case .goals: "Цели"
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
        case .goals: "target"
        case .purchaseQueue: "calendar.badge.plus"
        case .tradeHistory: "clock"
        case .dividends: "dollarsign.circle"
        case .analytics: "chart.bar.xaxis"
        case .notifications: "bell"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var selectedSectionRaw = AppSection.defaultSection.rawValue
    @State private var isAddingTransaction = false
    @State private var isAddingPlannedPurchase = false
    @State private var searchQuery = ""
    @State private var assetDetailRoute: AssetDetailRoute?

    private var selectedSection: AppSection {
        get { AppSection(rawValue: selectedSectionRaw) ?? AppSection.defaultSection }
        nonmutating set { selectedSectionRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    VestorLogoView(width: 138, height: 46)
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
                        ForEach(AppSection.primaryNavigation) { section in
                            Label(section.title, systemImage: section.icon)
                                .tag(section)
                        }
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
                if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SearchResultsView(query: searchQuery) { ticker in
                        assetDetailRoute = AssetDetailRoute(ticker: ticker)
                    }
                } else {
                    switch selectedSection {
                    case .overview:
                        DashboardView(isAddingTransaction: $isAddingTransaction)
                    case .goals:
                        GoalsView()
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
            }
            .navigationTitle(selectedSection.title)
            .searchable(text: $searchQuery, prompt: "Поиск тикера, сделки, заметки")
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
        .sheet(item: $assetDetailRoute) { route in
            AssetDetailView(ticker: route.ticker)
                .environmentObject(store)
        }
        .sheet(isPresented: Binding(
            get: { !store.setupState.isCompleted },
            set: { _ in }
        )) {
            OnboardingView()
                .environmentObject(store)
        }
    }
}

private struct VestorLogoView: View {
    let width: CGFloat
    let height: CGFloat

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
                    .scaledToFit()
            } else {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.teal)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
    }
}
