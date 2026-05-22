import SwiftUI

struct GlassPanel<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .liquidGlassSurface(cornerRadius: 16)
    }
}

struct CompanyLogoView: View {
    @EnvironmentObject private var store: PortfolioStore
    var ticker: String
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)

            if let url = store.companyLogoURL(for: ticker) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.18))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(size * 0.16)
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(String(ticker.normalizedTicker.prefix(1)))
            .font(.system(size: max(11, size * 0.42), weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var detail: String
    var systemImage: String
    var tone: MetricTone = .neutral

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tone.foreground)
                        .frame(width: 28, height: 28)
                        .background(tone.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum MetricTone {
    case neutral
    case positive
    case negative
    case accent

    var foreground: Color {
        switch self {
        case .neutral: .secondary
        case .positive: .green
        case .negative: .red
        case .accent: .accentColor
        }
    }

    var background: Color {
        foreground.opacity(0.14)
    }
}

extension View {
    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat) -> some View {
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
    }
}

struct EmptyPortfolioView: View {
    @Binding var isAddingTransaction: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Пока нет сделок")
                    .font(.title2.weight(.semibold))
                Text("Добавьте первую покупку акции, получите цену закрытия на дату сделки и обновите портфель.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                isAddingTransaction = true
            } label: {
                Label("Добавить сделку", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
