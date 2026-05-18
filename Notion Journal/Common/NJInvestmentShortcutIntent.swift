import Foundation

#if canImport(AppIntents)
import AppIntents

@available(iOS 16.0, *)
enum NJInvestmentShortcutMarketIntent: String, AppEnum {
    case smart
    case us
    case hk

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Investment Market"
    static var caseDisplayRepresentations: [NJInvestmentShortcutMarketIntent: DisplayRepresentation] = [
        .smart: "Smart",
        .us: "US",
        .hk: "HK"
    ]

    var routingMarket: NJInvestmentShortcutMarket {
        switch self {
        case .smart: return .smartDefault()
        case .us: return .us
        case .hk: return .hk
        }
    }
}

@available(iOS 16.0, *)
struct NJOpenInvestmentShortcutMenuIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Investment Shortcut"
    static var description = IntentDescription("Open a smart Investment menu for US or HK trading hours.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Market", default: .smart)
    var market: NJInvestmentShortcutMarketIntent

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$market) investment menu")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let routingMarket = market.routingMarket
        let defaults = UserDefaults(suiteName: "group.com.CYC.NotionJournal") ?? .standard
        defaults.set(routingMarket.rawValue, forKey: "nj_pending_investment_shortcut_market_v1")
        return .result(dialog: "Opening \(routingMarket.title) investment menu.")
    }
}

#endif
