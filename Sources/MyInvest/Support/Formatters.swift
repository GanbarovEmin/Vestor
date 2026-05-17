import Foundation

enum AppFormatters {
    static let usd: FloatingPointFormatStyle<Double>.Currency = .currency(code: "USD").locale(Locale(identifier: "ru_RU")).precision(.fractionLength(2))
    static let percent: FloatingPointFormatStyle<Double>.Percent = .percent.locale(Locale(identifier: "ru_RU")).precision(.fractionLength(2))
    static let shares: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0...4))
    static let price: FloatingPointFormatStyle<Double>.Currency = .currency(code: "USD").locale(Locale(identifier: "ru_RU")).precision(.fractionLength(2...4))

    static let compactDate: Date.FormatStyle = .dateTime.locale(Locale(identifier: "ru_RU")).day().month(.abbreviated).year()
    static let monthYear: Date.FormatStyle = .dateTime.locale(Locale(identifier: "ru_RU")).month(.wide).year()
}

extension Double {
    var asPercentRatio: Double {
        self
    }
}
