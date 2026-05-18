import Foundation

enum NJInvestmentShortcutMarket: String, CaseIterable, Identifiable {
    case us
    case hk

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .us: return "US"
        case .hk: return "HK"
        }
    }

    var investmentMarket: NJInvestmentMarket {
        switch self {
        case .us: return .us
        case .hk: return .hk
        }
    }

    nonisolated static func smartDefault(now: Date = Date()) -> NJInvestmentShortcutMarket {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .current
        let minuteOfDay = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        if minuteOfDay >= 20 * 60 + 30 || minuteOfDay < 5 * 60 {
            return .us
        }
        if minuteOfDay >= 9 * 60 && minuteOfDay <= 16 * 60 + 30 {
            return .hk
        }
        return .hk
    }

    nonisolated static func from(rawValue: String?) -> NJInvestmentShortcutMarket {
        guard let rawValue,
              let market = NJInvestmentShortcutMarket(rawValue: rawValue.lowercased()) else {
            return smartDefault()
        }
        return market
    }
}

enum NJInvestmentShortcutDestination: Identifiable {
    case macroCalendar(NJInvestmentShortcutMarket)
    case macroData(NJInvestmentShortcutMarket)
    case heatlist(NJInvestmentShortcutMarket)
    case trade(NJInvestmentShortcutMarket, NJInvestmentTradeTab)

    var id: String {
        switch self {
        case .macroCalendar(let market): return "\(market.rawValue).macroCalendar"
        case .macroData(let market): return "\(market.rawValue).macroData"
        case .heatlist(let market): return "\(market.rawValue).heatlist"
        case .trade(let market, let tab): return "\(market.rawValue).trade.\(tab.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .macroCalendar(let market):
            return "Macro Calendar for \(market.title)"
        case .macroData(let market):
            return "Macro Data for \(market.title)"
        case .heatlist(let market):
            return "Macro Data Heatlist for \(market.title)"
        case .trade(.us, .usQ1):
            return "2026 Q1 US Trade"
        case .trade(.us, .saasOvershoot):
            return "Q1 Software Overshoot Trade"
        case .trade(.hk, .chinaAI):
            return "HK / China Tech AI Trade"
        case .trade(.hk, .chinaHighYield):
            return "HK / China High Yield Trade"
        case .trade(_, let tab):
            return tab.rawValue
        }
    }

    var systemImageName: String {
        switch self {
        case .macroCalendar: return "calendar"
        case .macroData: return "list.bullet.rectangle"
        case .heatlist: return "square.grid.3x3.fill"
        case .trade(_, let tab): return tab.symbolName
        }
    }

    var market: NJInvestmentShortcutMarket {
        switch self {
        case .macroCalendar(let market),
             .macroData(let market),
             .heatlist(let market),
             .trade(let market, _):
            return market
        }
    }

    var section: NJInvestmentSection {
        switch self {
        case .macroCalendar: return .macro
        case .macroData: return .macroLine
        case .heatlist: return .macroLine
        case .trade: return .trades
        }
    }

    var tradeTab: NJInvestmentTradeTab? {
        if case .trade(_, let tab) = self { return tab }
        return nil
    }

    static func options(for market: NJInvestmentShortcutMarket) -> [NJInvestmentShortcutDestination] {
        switch market {
        case .us:
            return [
                .macroCalendar(.us),
                .macroData(.us),
                .heatlist(.us),
                .trade(.us, .usQ1),
                .trade(.us, .saasOvershoot)
            ]
        case .hk:
            return [
                .macroCalendar(.hk),
                .macroData(.hk),
                .heatlist(.hk),
                .trade(.hk, .chinaAI),
                .trade(.hk, .chinaHighYield)
            ]
        }
    }
}
