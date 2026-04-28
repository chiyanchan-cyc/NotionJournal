import SwiftUI
import Charts
import UIKit

private enum NJInvestmentMarket: String, CaseIterable, Identifiable {
    case all = "All"
    case us = "US"
    case chinaHK = "HK / China"
    case japan = "Japan"
    case europe = "Europe"
    case crypto = "Commodity / Crypto"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .all: return "globe"
        case .us: return "building.columns"
        case .chinaHK: return "dollarsign.arrow.circlepath"
        case .japan: return "yensign.circle"
        case .europe: return "eurosign.circle"
        case .crypto: return "bitcoinsign.circle"
        }
    }

    func matches(region: String) -> Bool {
        let value = region.lowercased()
        switch self {
        case .all:
            return true
        case .us:
            return value.contains("us") || value.contains("united states")
        case .chinaHK:
            return value.contains("china") || value.contains("hk") || value.contains("hong kong")
        case .japan:
            return value.contains("japan")
        case .europe:
            return value.contains("europe") || value.contains("euro") || value.contains("ecb") || value.contains("germany") || value.contains("france") || value.contains("uk") || value.contains("united kingdom")
        case .crypto:
            return value.contains("crypto") || value.contains("bitcoin") || value.contains("btc") || value.contains("commodity") || value.contains("oil") || value.contains("gold") || value.contains("silver")
        }
    }
}

enum NJInvestmentSection: String, CaseIterable, Identifiable {
    case macro = "Macro"
    case macroLine = "Macro Line View"
    case observations = "Weekly Observation"
    case trades = "Trade Thesis"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .macro: return "globe.americas"
        case .macroLine: return "list.bullet.rectangle"
        case .observations: return "scope"
        case .trades: return "chart.xyaxis.line"
        }
    }
}

enum NJInvestmentTradeTab: String, CaseIterable, Identifiable {
    case saasOvershoot = "SaaS Overshoot Trade"
    case chinaAI = "China AI Trade"
    case globalAIInfrastructure = "Global AI Infrastructure Trade"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .saasOvershoot: return "arrow.down.right.and.arrow.up.left"
        case .chinaAI: return "cpu"
        case .globalAIInfrastructure: return "bolt.horizontal.circle"
        }
    }
}

private enum NJInvestmentCalendarMode: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
}

private struct NJInvestmentObservation: Identifiable {
    let id: String
    let title: String
    let market: NJInvestmentMarket
    let timeframe: String
    let confidence: String
    let thesis: String
    let confirm: String
    let invalidate: String
    let status: String
}

private struct NJInvestmentTradeThesis: Identifiable {
    let id: String
    let title: String
    let market: NJInvestmentMarket
    let status: String
    let premise: String
    let watch: String
    let invalidation: String
}

private struct NJInvestmentMarketChecklist: Identifiable {
    let id: String
    let market: NJInvestmentMarket
    let title: String
    let items: [String]
}

private struct NJInvestmentSnapshotMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let change: String
    let detail: String
}

private struct NJInvestmentLinePoint: Identifiable {
    let id: String
    let dateKey: String
    let value: String
    let change: String
    let isDown: Bool
}

private struct NJInvestmentChartPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let change: String
    let isDown: Bool
}

private struct NJInvestmentMacroSignal: Identifiable {
    let id: String
    let market: NJInvestmentMarket
    let title: String
    let status: String
    let note: String
    let nextCatalyst: String
}

private struct NJInvestmentWatchRow: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let monitorDate: String
    let initialPrice: String
    let week52High: String
    let week52Low: String
    let todayPrice: String
    let percentChange: String

    var percentFrom52WeekHigh: String {
        percentDistance(from: week52High)
    }

    var percentFrom52WeekLow: String {
        percentDistance(from: week52Low)
    }

    var percentFromInitialPrice: String {
        percentDistance(from: initialPrice)
    }

    private func percentDistance(from anchor: String) -> String {
        guard let price = Self.numericValue(from: todayPrice),
              let anchorValue = Self.numericValue(from: anchor),
              anchorValue != 0 else { return "n/a" }
        let pct = (price / anchorValue - 1) * 100
        return String(format: "%+.1f%%", pct)
    }

    private static func numericValue(from text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "HK$", with: "")
            .replacingOccurrences(of: "CNY", with: "")
            .replacingOccurrences(of: "EUR", with: "")
            .replacingOccurrences(of: "JPY", with: "")
        let pattern = #"[-+]?\d*\.?\d+"#
        guard let range = cleaned.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(cleaned[range])
    }
}

private struct NJInvestmentWatchColumn: Identifiable {
    let id: String
    let title: String
    let defaultWeight: CGFloat
}

private struct NJInvestmentKPIRow: Identifiable {
    let id: String
    let trade: String
    let kpi: String
    let target: String
    let current: String
    let actionRule: String
}

private struct NJInvestmentActualTradeRow: Identifiable {
    let id: String
    let trade: String
    let symbol: String
    let position: String
    let entry: String
    let thesisStatus: String
}

private struct NJInvestmentMovementRow: Identifiable {
    let id: String
    let date: String
    let symbol: String
    let move: String
    let read: String
    let nextStep: String
}

private struct NJInvestmentCompactCalendarRow: Identifiable {
    let id: String
    let cell: (key: String, day: Int?, isToday: Bool)
    let events: [NJFinanceMacroEvent]
    let snapshots: [(text: String, isDown: Bool)]
}

struct NJInvestmentModuleView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedMarket: NJInvestmentMarket = .all
    @State private var focusedMonth: Date = Date()
    @State private var calendarMode: NJInvestmentCalendarMode = .month
    @State private var eventsByDate: [String: [NJFinanceMacroEvent]] = [:]
    @State private var selectedEvent: NJFinanceMacroEvent? = nil
    @State private var selectedWatchRow: NJInvestmentWatchRow? = nil
    @State private var tradeWatchlistExpanded = true
    @State private var tradeKPIExpanded = true
    @State private var tradeActualExpanded = true
    @State private var tradeMovementExpanded = true
    @State private var selectedSnapshotLineID = "spx"
    @State private var watchColumnEditorExpanded = false
    @AppStorage("nj_investment_watch_hidden_columns_v1") private var watchHiddenColumnsStorage = ""
    @AppStorage("nj_investment_watch_column_widths_v1") private var watchColumnWidthsStorage = ""

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        return cal
    }()

    private let watchColumns: [NJInvestmentWatchColumn] = [
        NJInvestmentWatchColumn(id: "symbol", title: "Symbol", defaultWeight: 0.9),
        NJInvestmentWatchColumn(id: "name", title: "Name", defaultWeight: 1.55),
        NJInvestmentWatchColumn(id: "initialPrice", title: "Initial Price", defaultWeight: 1.05),
        NJInvestmentWatchColumn(id: "week52High", title: "52W High", defaultWeight: 1.0),
        NJInvestmentWatchColumn(id: "week52Low", title: "52W Low", defaultWeight: 1.0),
        NJInvestmentWatchColumn(id: "todayPrice", title: "Today Price", defaultWeight: 1.1),
        NJInvestmentWatchColumn(id: "dayChange", title: "Day %", defaultWeight: 0.75),
        NJInvestmentWatchColumn(id: "fromInitial", title: "% From Initial", defaultWeight: 1.1),
        NJInvestmentWatchColumn(id: "fromHigh", title: "% From 52W High", defaultWeight: 1.15),
        NJInvestmentWatchColumn(id: "fromLow", title: "% From 52W Low", defaultWeight: 1.15)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isCompactLayout {
                    compactInvestmentNavigation
                }

                switch store.selectedInvestmentSection {
                case .macro:
                    macroWorkspace
                case .macroLine:
                    macroLineWorkspace
                case .observations:
                    deferredWorkspace(title: "Weekly Observation", icon: "scope")
                case .trades:
                    tradeWorkspace
                }
            }
            .padding(isCompactLayout ? 10 : 18)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Investment")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reloadEvents() }
        .onChange(of: focusedMonth) { _, _ in reloadEvents() }
        .onChange(of: calendarMode) { _, _ in reloadEvents() }
        .onChange(of: selectedMarket) { _, _ in reloadEvents() }
        .onReceive(NotificationCenter.default.publisher(for: .njPullCompleted)) { _ in reloadEvents() }
        .sheet(item: $selectedEvent) { event in
            NavigationStack {
                ScrollView {
                    eventResearchPanel(event, showsCloseButton: false)
                        .padding(16)
                }
                .background(Color(UIColor.systemGroupedBackground))
                .navigationTitle("Event Research")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            selectedEvent = nil
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedWatchRow) { row in
            NavigationStack {
                ScrollView {
                    watchResearchPanel(row)
                        .padding(16)
                }
                .background(Color(UIColor.systemGroupedBackground))
                .navigationTitle(row.symbol)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            selectedWatchRow = nil
                        }
                    }
                }
            }
        }
    }

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var compactInvestmentNavigation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Investment", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline.weight(.bold))
                Spacer()
                Menu {
                    ForEach(NJInvestmentSection.allCases) { section in
                        Button {
                            store.selectedInvestmentSection = section
                        } label: {
                            Label(section.rawValue, systemImage: section.symbolName)
                        }
                    }
                } label: {
                    Label(store.selectedInvestmentSection.rawValue, systemImage: store.selectedInvestmentSection.symbolName)
                        .font(.subheadline.weight(.semibold))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NJInvestmentSection.allCases) { section in
                        Button {
                            store.selectedInvestmentSection = section
                        } label: {
                            Label(section.rawValue, systemImage: section.symbolName)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(store.selectedInvestmentSection == section ? Color.accentColor.opacity(0.18) : Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if store.selectedInvestmentSection == .trades {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(NJInvestmentTradeTab.allCases) { tab in
                            Button {
                                store.selectedInvestmentTradeTab = tab
                            } label: {
                                Label(tab.rawValue, systemImage: tab.symbolName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(store.selectedInvestmentTradeTab == tab ? Color.accentColor.opacity(0.18) : Color(UIColor.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var macroWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            macroCalendar
            marketChecklistGrid
        }
    }

    private var macroLineWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Macro Line View")
                    .font(.title2.weight(.bold))
                Text("A non-calendar read of the macro dashboard, signals, and monitored data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            marketPicker
            marketSnapshotStrip
            marketSnapshotLineView
            macroSignalScorecard

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Signal Feed", icon: "list.bullet.rectangle")
                ForEach(filteredMacroSignals) { signal in
                    macroSignalLine(signal)
                }
            }
            .padding(14)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Tracked Inputs", icon: "checklist")
                ForEach(filteredChecklists) { checklist in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(checklist.title, systemImage: checklist.market.symbolName)
                            .font(.headline)
                        ForEach(checklist.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .padding(.top, 7)
                                    .foregroundStyle(.secondary)
                                Text(item)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var tradeWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Trade Thesis")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Label("Monitoring Active", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text("Pinned operating blocks stay on top. Conversation blocks are newest first. When a trade ends, heartbeat stops monitoring it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            switch store.selectedInvestmentTradeTab {
            case .saasOvershoot:
                saasOvershootWorkspace
            case .chinaAI:
                chinaAIWorkspace
            case .globalAIInfrastructure:
                globalAIInfrastructureWorkspace
            }
        }
    }

    private var saasOvershootWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SaaS Overshoot Trade")
                            .font(.title2.weight(.bold))
                        Text("Buying expectation mismatch, not a broad SaaS recovery.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Monitoring Active", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text("Core idea: SaaS was sold aggressively on AI fear, headcount reduction, and cloud optimization. Demand slowed, not collapsed, and expectations may now be too low.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            tradeCollapsibleBlock(title: "Watch List", icon: "binoculars", isExpanded: $tradeWatchlistExpanded) {
                watchListTable(rows: watchListRows)
            }

            tradeCollapsibleBlock(title: "Target KPI Workspace", icon: "target", isExpanded: $tradeKPIExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    tradeSubsectionTitle("Entry Conditions")
                    tradeTableHeader(["Phase", "Condition", "Size", "Rule"], widths: [0.9, 1.8, 0.9, 2.0])
                    tradeTableRow(["Before earnings", "Starter only", "Max 30%", "Pick 2-3 names max. No diversification."], widths: [0.9, 1.8, 0.9, 2.0])
                    tradeTableRow(["After earnings", "This is the trade", "Add / cut / exit", "Market reaction to good numbers decides validity."], widths: [0.9, 1.8, 0.9, 2.0])

                    tradeSubsectionTitle("Earnings Decision Matrix")
                    tradeTableHeader(["Result", "Stock Reaction", "Action", "Meaning"], widths: [1.1, 1.1, 1.1, 2.2])
                    tradeTableRow(["Beat", "Up", "Add hard", "Market confirms expectations were too low."], widths: [1.1, 1.1, 1.1, 2.2])
                    tradeTableRow(["Beat", "Flat", "Cut", "Good numbers are not being rewarded enough."], widths: [1.1, 1.1, 1.1, 2.2])
                    tradeTableRow(["Beat", "Down", "Exit immediately", "Trade invalid. No debate."], widths: [1.1, 1.1, 1.1, 2.2])

                    tradeSubsectionTitle("Target Strategy")
                    tradeTableHeader(["Rule", "Target", "Timeframe", "Notes"], widths: [1.2, 1.2, 1.0, 2.0])
                    tradeTableRow(["Trade these only", "DDOG, MDB, TEAM, NET, SNOW", "Earnings window", "Do not touch ZM, ASAN, or anything without prior punishment."], widths: [1.2, 1.2, 1.0, 2.0])
                    tradeTableRow(["Max positions", "3", "Active trade", "Concentration is part of the edge."], widths: [1.2, 1.2, 1.0, 2.0])

                    tradeSubsectionTitle("Projected Profit / Risk")
                    tradeTableHeader(["Target", "Window", "Failure Rule", "Risk Rule"], widths: [1.0, 1.0, 1.8, 1.8])
                    tradeTableRow(["+10% to +25%", "1-3 days", "If it does not move, we are wrong: exit.", "No averaging down. No holding through second drop. Cut losers fast."], widths: [1.0, 1.0, 1.8, 1.8])
                }
            }

            tradeCollapsibleBlock(title: "Actual Trades", icon: "rectangle.stack.badge.plus", isExpanded: $tradeActualExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    tradeTableHeader(["Trade", "Symbol", "Position", "Entry", "Thesis"], widths: [1.3, 0.75, 1.3, 1.1, 1.5])
                    tradeTableRow(["SaaS Overshoot", "-", "None recorded", "-", "No real trade until user confirms execution."], widths: [1.3, 0.75, 1.3, 1.1, 1.5])
                }
            }

            tradeCollapsibleBlock(title: "Movement Log", icon: "waveform.path.ecg", isExpanded: $tradeMovementExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    tradeTableHeader(["Date", "Symbol", "Move", "Read", "Next"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "DDOG", "Needs refresh", "Check if priority name is moving toward reward-after-earnings setup.", "Heartbeat update"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "MDB", "Needs refresh", "Best asymmetry candidate; monitor whether punishment has reset expectations.", "Heartbeat update"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "TEAM", "Needs refresh", "Seat-risk test; watch whether demand concerns remain overdone.", "Heartbeat update"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "NET", "Needs refresh", "Hybrid asymmetry candidate; monitor reward/punishment pattern.", "Heartbeat update"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "SNOW", "Needs refresh", "High risk / high reward only; usage reset can still be dangerous.", "Heartbeat update"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Conversation Timeline - Newest First", icon: "bubble.left.and.bubble.right")
                tradeConversationPlaceholder(role: "Me", kind: "Thesis", title: "Core thesis", body: "Market expectations are too low after AI fear, headcount reduction, and cloud optimization. We are betting on expectation mismatch, not SaaS recovery.")
                tradeConversationPlaceholder(role: "System", kind: "Rule", title: "Final rule", body: "If the market does not reward good numbers, the trade is invalid. Exit.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var chinaAIWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("China AI Trade (Full Stack)")
                            .font(.title2.weight(.bold))
                        Text("China AI wins on scarcity, not superiority.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Monitoring Active", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text("Core thesis: constrained supply inside the China AI stack creates pricing power, quota rationing, and better near-term unit economics than the US price-war model.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            tradeCollapsibleBlock(title: "Watch List", icon: "binoculars", isExpanded: $tradeWatchlistExpanded) {
                watchListTable(rows: chinaAIWatchListRows)
            }

            tradeCollapsibleBlock(title: "Target KPI Workspace", icon: "target", isExpanded: $tradeKPIExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    tradeSubsectionTitle("Entry Conditions")
                    tradeTableHeader(["Phase", "Condition", "Size", "Rule"], widths: [0.9, 1.8, 0.9, 2.0])
                    tradeTableRow(["Scarcity", "Price hikes / quotas visible", "Starter only", "Enter when token pricing rises or cloud quotas tighten in public checks."], widths: [0.9, 1.8, 0.9, 2.0])
                    tradeTableRow(["Policy", "Support confirmed", "Add selectively", "Add only when policy and monetization are both visible."], widths: [0.9, 1.8, 0.9, 2.0])
                    tradeTableRow(["Adoption", "Enterprise contracts real", "Scale with proof", "Demand rhetoric alone is not enough; require monetization evidence."], widths: [0.9, 1.8, 0.9, 2.0])

                    tradeSubsectionTitle("Checklist")
                    tradeTableHeader(["Signal", "Target", "Current", "Action Rule"], widths: [1.2, 1.2, 1.0, 2.3])
                    tradeTableRow(["Pricing", "Rising", "Needs refresh", "Treat price hikes as the cleanest scarcity confirmation."], widths: [1.2, 1.2, 1.0, 2.3])
                    tradeTableRow(["Rationing", "Present", "Needs refresh", "Quota restrictions should confirm constrained supply, not soft demand."], widths: [1.2, 1.2, 1.0, 2.3])
                    tradeTableRow(["Enterprise adoption", "Real contracts", "Needs refresh", "Ignore narrative strength if revenue conversion is absent."], widths: [1.2, 1.2, 1.0, 2.3])
                    tradeTableRow(["Government support", "Active", "Needs refresh", "Policy support matters only if deployment and procurement follow."], widths: [1.2, 1.2, 1.0, 2.3])

                    tradeSubsectionTitle("Trade Expression")
                    tradeTableHeader(["Leg", "Exposure", "Timeframe", "Notes"], widths: [1.0, 1.5, 1.0, 2.2])
                    tradeTableRow(["Apps / cloud", "BIDU, BABA, 0700 HK", "Ongoing", "Higher-quality monetization layer if pricing power persists."], widths: [1.0, 1.5, 1.0, 2.2])
                    tradeTableRow(["Domestic compute", "0981 HK, 688256 CN", "Ongoing", "Higher beta to policy support and supply bottlenecks."], widths: [1.0, 1.5, 1.0, 2.2])
                    tradeTableRow(["Packaging", "600584 CN, 002156 CN, 002185 CN", "Ongoing", "Backend beneficiaries if local demand broadens through the stack."], widths: [1.0, 1.5, 1.0, 2.2])

                    tradeSubsectionTitle("Exit Conditions")
                    tradeTableHeader(["Trigger", "Read", "Action", "Meaning"], widths: [1.1, 1.3, 1.0, 1.8])
                    tradeTableRow(["Supply expansion", "Rapid", "Reduce", "Scarcity edge fades if capacity appears faster than demand."], widths: [1.1, 1.3, 1.0, 1.8])
                    tradeTableRow(["Pricing", "Declining", "Cut", "Price cuts would directly weaken the thesis."], widths: [1.1, 1.3, 1.0, 1.8])
                    tradeTableRow(["Utilization", "Weakening", "Exit", "No visible monetization means the thesis was too narrative-heavy."], widths: [1.1, 1.3, 1.0, 1.8])
                }
            }

            tradeCollapsibleBlock(title: "Actual Trades", icon: "rectangle.stack.badge.plus", isExpanded: $tradeActualExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    tradeTableHeader(["Trade", "Symbol", "Position", "Entry", "Thesis"], widths: [1.3, 0.75, 1.3, 1.1, 1.5])
                    tradeTableRow(["China AI", "-", "None recorded", "-", "No real trade until user confirms execution."], widths: [1.3, 0.75, 1.3, 1.1, 1.5])
                }
            }

            tradeCollapsibleBlock(title: "Movement Log", icon: "waveform.path.ecg", isExpanded: $tradeMovementExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    tradeTableHeader(["Date", "Symbol", "Move", "Read", "Next"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "BABA", "Needs refresh", "Cloud and application layer should confirm monetization before compute beta leads alone.", "Check pricing / contract news"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "0700 HK", "Needs refresh", "Tencent should validate enterprise deployment and platform monetization.", "Check AI product and cloud updates"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "0981 HK", "Needs refresh", "Domestic compute strength should follow scarcity and policy support, not pure narrative.", "Check capex / capacity headlines"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "688256 CN", "Needs refresh", "Cambricon is high beta to domestic model demand but also to monetization disappointment.", "Check adoption and procurement"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "USD/CNH", "Needs refresh", "A stable or stronger CNH helps confirm policy confidence and local-risk appetite.", "Compare with HSI and platform beta"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Conversation Timeline - Newest First", icon: "bubble.left.and.bubble.right")
                tradeConversationPlaceholder(role: "Me", kind: "Thesis", title: "Scarcity thesis", body: "China AI can earn better near-term economics because constrained supply allows quota rationing and firmer pricing.")
                tradeConversationPlaceholder(role: "System", kind: "Risk", title: "Main failure mode", body: "If price cuts appear before monetization is visible, the scarcity edge likely was overstated.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var globalAIInfrastructureWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Global AI Infrastructure Trade")
                            .font(.title2.weight(.bold))
                        Text("Sell AI hype, buy AI electricity.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Monitoring Active", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text("Core thesis: the AI buildout is a global infrastructure cycle driven by power, copper, transformers, cooling, and grid expansion more than near-term software monetization.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            tradeCollapsibleBlock(title: "Watch List", icon: "binoculars", isExpanded: $tradeWatchlistExpanded) {
                watchListTable(rows: globalAIInfrastructureWatchListRows)
            }

            tradeCollapsibleBlock(title: "Target KPI Workspace", icon: "target", isExpanded: $tradeKPIExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    tradeSubsectionTitle("Entry Conditions")
                    tradeTableHeader(["Phase", "Condition", "Size", "Rule"], widths: [0.9, 1.8, 0.9, 2.0])
                    tradeTableRow(["Capex", "Data-center capex rising", "Starter only", "Enter when capex announcements flow through to physical infrastructure orders."], widths: [0.9, 1.8, 0.9, 2.0])
                    tradeTableRow(["Power", "Shortage signals visible", "Add selectively", "Add when grid stress and power scarcity validate the bottleneck thesis."], widths: [0.9, 1.8, 0.9, 2.0])
                    tradeTableRow(["Materials", "Copper demand accelerating", "Scale with proof", "Treat copper demand as confirmation that buildout is real, not just narrative."], widths: [0.9, 1.8, 0.9, 2.0])

                    tradeSubsectionTitle("Checklist")
                    tradeTableHeader(["Signal", "Target", "Current", "Action Rule"], widths: [1.2, 1.2, 1.0, 2.3])
                    tradeTableRow(["Power demand", "Rising", "Needs refresh", "Utilities and power merchants should confirm that AI load growth is real."], widths: [1.2, 1.2, 1.0, 2.3])
                    tradeTableRow(["Grid bottlenecks", "Visible", "Needs refresh", "Transformer backlog and connection delays validate the grid leg."], widths: [1.2, 1.2, 1.0, 2.3])
                    tradeTableRow(["Copper demand", "Sustained", "Needs refresh", "Copper should lead if the physical buildout thesis is correct."], widths: [1.2, 1.2, 1.0, 2.3])
                    tradeTableRow(["Infrastructure backlog", "Growing", "Needs refresh", "Backlog growth is cleaner than generic AI commentary."], widths: [1.2, 1.2, 1.0, 2.3])

                    tradeSubsectionTitle("Trade Expression")
                    tradeTableHeader(["Leg", "Exposure", "Timeframe", "Notes"], widths: [1.0, 1.5, 1.0, 2.2])
                    tradeTableRow(["Copper", "FCX, SCCO, 2899 HK", "Ongoing", "Direct demand read-through from power and data-center buildout."], widths: [1.0, 1.5, 1.0, 2.2])
                    tradeTableRow(["Grid equipment", "ETN, SU FP, ENR GR, 6501 JP", "Ongoing", "Best expression of transformer, switchgear, and grid-capex bottlenecks."], widths: [1.0, 1.5, 1.0, 2.2])
                    tradeTableRow(["Power / cooling", "NEE, DUK, VST, VRT, JCI, TT", "Ongoing", "Utilities and data-center infrastructure capture the energy-demand angle."], widths: [1.0, 1.5, 1.0, 2.2])

                    tradeSubsectionTitle("Exit Conditions")
                    tradeTableHeader(["Trigger", "Read", "Action", "Meaning"], widths: [1.1, 1.3, 1.0, 1.8])
                    tradeTableRow(["AI capex", "Slowing", "Reduce", "If hyperscaler spending slows, the second-derivative support fades."], widths: [1.1, 1.3, 1.0, 1.8])
                    tradeTableRow(["Copper demand", "Weakening", "Cut", "Commodity weakness would directly challenge the buildout thesis."], widths: [1.1, 1.3, 1.0, 1.8])
                    tradeTableRow(["Supply", "Catching up", "Exit", "Overcapacity signs mean pricing power and backlog quality are rolling over."], widths: [1.1, 1.3, 1.0, 1.8])
                }
            }

            tradeCollapsibleBlock(title: "Actual Trades", icon: "rectangle.stack.badge.plus", isExpanded: $tradeActualExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    tradeTableHeader(["Trade", "Symbol", "Position", "Entry", "Thesis"], widths: [1.3, 0.75, 1.3, 1.1, 1.5])
                    tradeTableRow(["Global AI Infra", "-", "None recorded", "-", "No real trade until user confirms execution."], widths: [1.3, 0.75, 1.3, 1.1, 1.5])
                }
            }

            tradeCollapsibleBlock(title: "Movement Log", icon: "waveform.path.ecg", isExpanded: $tradeMovementExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    tradeTableHeader(["Date", "Symbol", "Move", "Read", "Next"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "FCX", "Needs refresh", "Copper should confirm the trade before grid names fully rerate.", "Check copper and mine commentary"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "VST", "Needs refresh", "Power merchants should reflect scarcity faster than regulated utilities.", "Check power pricing and demand updates"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "ETN", "Needs refresh", "Transformer and switchgear backlog are core confirmation signals.", "Check backlog / order commentary"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "VRT", "Needs refresh", "Cooling and data-center infrastructure should validate capex conversion.", "Check data-center order flow"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                    tradeTableRow(["Daily", "Copper", "Needs refresh", "Sustained copper strength is the cleanest macro confirmation for the infrastructure thesis.", "Compare miners vs spot copper"], widths: [0.9, 0.75, 0.9, 1.9, 1.45])
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Conversation Timeline - Newest First", icon: "bubble.left.and.bubble.right")
                tradeConversationPlaceholder(role: "Me", kind: "Thesis", title: "Infrastructure thesis", body: "The durable AI winners may be power, copper, grid equipment, and cooling rather than whichever software model is winning this quarter.")
                tradeConversationPlaceholder(role: "System", kind: "Risk", title: "Main failure mode", body: "If AI capex slows or copper/grid bottlenecks ease quickly, the whole physical-infrastructure rerating can compress.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func tradeCollapsibleBlock<Content: View>(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ScrollView(.horizontal, showsIndicators: true) {
                content()
                    .frame(minWidth: 840, alignment: .leading)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.headline.weight(.semibold))
                Label("Pinned", systemImage: "pin.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tradeConversationPlaceholder(role: String, kind: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(role)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(kind)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer()
                Text("Newest first")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tradeSubsectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .padding(.top, 4)
    }

    private func watchListTable(rows: [NJInvestmentWatchRow]) -> some View {
        let columns = visibleWatchColumns
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.snappy) {
                        watchColumnEditorExpanded.toggle()
                    }
                } label: {
                    Label(watchColumnEditorExpanded ? "Hide Column Tools" : "Columns", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Reset Local Layout") {
                    watchHiddenColumnsStorage = ""
                    watchColumnWidthsStorage = ""
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }

            if watchColumnEditorExpanded {
                watchColumnEditor
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    tradeTableHeader(columns.map(\.title), widths: columns.map { watchColumnWeight($0.id) })
                    ForEach(rows) { row in
                        Button {
                            selectedWatchRow = row
                        } label: {
                            tradeTableRow(
                                columns.map { watchValue(for: row, columnID: $0.id) },
                                widths: columns.map { watchColumnWeight($0.id) },
                                emphasizedDownColumns: columns.enumerated().compactMap { index, column in
                                    watchValueIsDown(for: row, columnID: column.id) ? index : nil
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: max(watchTableWidth(for: columns), 320), alignment: .leading)
            }
        }
    }

    private var watchColumnEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(watchColumns) { column in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: watchColumnVisibleBinding(column.id)) {
                        Text(column.title)
                            .font(.caption.weight(.semibold))
                    }
                    .toggleStyle(.switch)

                    if !hiddenWatchColumnIDs.contains(column.id) {
                        HStack(spacing: 8) {
                            Text("Width")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: watchColumnWidthBinding(column.id), in: 0.55...1.9, step: 0.05)
                            Text(String(format: "%.2fx", watchColumnWeight(column.id)))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var visibleWatchColumns: [NJInvestmentWatchColumn] {
        let hidden = hiddenWatchColumnIDs
        let visible = watchColumns.filter { !hidden.contains($0.id) }
        return visible.isEmpty ? watchColumns.prefix(1).map { $0 } : visible
    }

    private var hiddenWatchColumnIDs: Set<String> {
        Set(watchHiddenColumnsStorage.split(separator: ",").map(String.init))
    }

    private var watchColumnWidths: [String: CGFloat] {
        Dictionary(uniqueKeysWithValues: watchColumnWidthsStorage
            .split(separator: ";")
            .compactMap { item -> (String, CGFloat)? in
                let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2, let value = Double(parts[1]) else { return nil }
                return (parts[0], CGFloat(value))
            })
    }

    private func watchColumnWeight(_ id: String) -> CGFloat {
        if let local = watchColumnWidths[id] {
            return min(max(local, 0.55), 1.9)
        }
        return watchColumns.first(where: { $0.id == id })?.defaultWeight ?? 1
    }

    private func watchColumnVisibleBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenWatchColumnIDs.contains(id) },
            set: { isVisible in
                var hidden = hiddenWatchColumnIDs
                if isVisible {
                    hidden.remove(id)
                } else if hidden.count < watchColumns.count - 1 {
                    hidden.insert(id)
                }
                watchHiddenColumnsStorage = hidden.sorted().joined(separator: ",")
            }
        )
    }

    private func watchColumnWidthBinding(_ id: String) -> Binding<Double> {
        Binding(
            get: { Double(watchColumnWeight(id)) },
            set: { value in
                var widths = watchColumnWidths
                widths[id] = CGFloat(value)
                watchColumnWidthsStorage = widths
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(String(format: "%.2f", Double($0.value)))" }
                    .joined(separator: ";")
            }
        )
    }

    private func watchValue(for row: NJInvestmentWatchRow, columnID: String) -> String {
        switch columnID {
        case "symbol": return row.symbol
        case "name": return row.name
        case "monitorDate": return row.monitorDate
        case "initialPrice": return row.initialPrice
        case "week52High": return row.week52High
        case "week52Low": return row.week52Low
        case "todayPrice": return row.todayPrice
        case "dayChange": return row.percentChange
        case "fromInitial": return row.percentFromInitialPrice
        case "fromHigh": return row.percentFrom52WeekHigh
        case "fromLow": return row.percentFrom52WeekLow
        default: return ""
        }
    }

    private func watchValueIsDown(for row: NJInvestmentWatchRow, columnID: String) -> Bool {
        switch columnID {
        case "dayChange", "fromInitial", "fromHigh", "fromLow":
            return watchValue(for: row, columnID: columnID).hasPrefix("-")
        default:
            return false
        }
    }

    private func watchResearchPanel(_ row: NJInvestmentWatchRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(row.symbol) - \(row.name)")
                            .font(.title2.weight(.bold))
                        Text("Initial \(row.initialPrice) -> current \(row.todayPrice) (\(row.percentFromInitialPrice) from initial)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(row.percentFromInitialPrice.hasPrefix("-") ? Color.red : Color.green)
                    }
                    Spacer()
                    Text(row.percentChange)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(row.percentChange.hasPrefix("-") ? Color.red : Color.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((row.percentChange.hasPrefix("-") ? Color.red : Color.green).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if row.symbol == "DDOG" {
                ddogResearchPanel
            } else {
                genericWatchResearchPanel(row)
            }
        }
    }

    private var ddogResearchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            researchCard(title: "What It Does", status: "Core product") {
                Text("Datadog is a usage-based observability and cloud security platform. It monitors infrastructure, application performance, logs, user experience, cloud security, and related production data in one real-time platform.")
            }

            researchCard(title: "Trade Read", status: "Fits SaaS Overshoot") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This is a better fit for the SaaS Overshoot trade than a pure seat-based software name because the bear case is mostly usage reset, cloud optimization, and AI disruption fear.")
                    Text("The bull case is that AI workloads make production systems more complex, which raises the need for observability instead of eliminating it. If earnings show broad demand and the stock is rewarded, DDOG is eligible to add hard under our rule.")
                }
            }

            researchCard(title: "Headcount Exposure", status: "Lower direct risk") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DDOG is not mainly a headcount-seat story like TEAM. Lower developer or IT headcount can still hurt indirectly, but the more important variable is workload volume: cloud usage, logs, traces, security events, AI inference traffic, and production incidents.")
                    Text("So the question is not simply 'are companies hiring?' The question is whether monitored infrastructure and AI/cloud complexity keep expanding enough to offset cloud optimization.")
                }
            }

            researchCard(title: "Related News", status: "Watch May 7") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Datadog announced its Q1 FY2026 earnings call for May 7, 2026. That is the next clean catalyst for this trade.")
                    Text("Recent company materials emphasize AI observability: its 2026 AI Engineering report says production AI systems are hitting operational limits, with capacity and reliability failures creating monitoring demand.")
                    Text("Q4/FY2025 results guided FY2026 revenue to roughly $4.06B-$4.10B, and Q1 guidance to about $951M-$961M. The market will likely focus on whether growth excluding the biggest AI-native customer is broad enough.")
                    Text("Risk headline: some analysts have focused on large-customer concentration, including OpenAI exposure, and whether core growth can offset that.")
                }
            }

            researchCard(title: "Decision Rule", status: "No debate") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Before earnings: starter only, max 30%, and only if we want DDOG as one of the 2-3 SaaS names.")
                    Text("After earnings: beat + stock up means add hard. Beat + flat means cut. Beat + down means exit immediately.")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Sources")
                    .font(.caption.weight(.bold))
                Text("Datadog investor release Apr 16, 2026; Datadog State of AI Engineering 2026; Datadog Q4/FY2025 results; Investing.com earnings risk note.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func genericWatchResearchPanel(_ row: NJInvestmentWatchRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            researchCard(title: "Research Needed", status: "Template") {
                Text("This row is now clickable. Next pass should fill the same trade-specific research structure for \(row.name): what it does, why it belongs in this trade, key risk, catalyst, and latest related news.")
            }
            researchCard(title: "Current Watch Read", status: "Price anchor") {
                Text("\(row.name) is \(row.percentFromInitialPrice) from the initial watch price and \(row.percentFrom52WeekHigh) from its 52-week high.")
            }
        }
    }

    private func researchCard<Content: View>(title: String, status: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(status)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            content()
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func watchTableWidth(for columns: [NJInvestmentWatchColumn]) -> CGFloat {
        let spacingWidth = CGFloat(max(columns.count - 1, 0)) * 8
        return columns.map { watchColumnWidth(for: $0.id, totalWeight: columns.map { watchColumnWeight($0.id) }.reduce(0, +)) }.reduce(0, +) + spacingWidth + 20
    }

    private func watchColumnWidth(for id: String, totalWeight: CGFloat) -> CGFloat {
        let tableWidth: CGFloat = isCompactLayout ? 760 : 960
        let weight = watchColumnWeight(id)
        return tableWidth * weight / max(totalWeight, 1)
    }

    private func tradeTableHeader(_ values: [String], widths: [CGFloat]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: tradeColumnWidth(at: index, widths: widths), alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func tradeTableRow(_ values: [String], widths: [CGFloat], emphasizedDownColumns: [Int] = []) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.caption)
                    .foregroundStyle(emphasizedDownColumns.contains(index) ? Color.red : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: tradeColumnWidth(at: index, widths: widths), alignment: .topLeading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func tradeColumnWidth(at index: Int, widths: [CGFloat]) -> CGFloat {
        let tableWidth: CGFloat = 800
        let spacingWidth = CGFloat(max(widths.count - 1, 0)) * 8
        let contentWidth = tableWidth - spacingWidth
        let totalWeight = max(widths.reduce(0, +), 1)
        let weight = widths.indices.contains(index) ? widths[index] : 1
        return contentWidth * weight / totalWeight
    }

    private func deferredWorkspace(title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.bold))
            Text("Kept out of Macro for now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .padding(18)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                topBarTitle
                Spacer(minLength: 8)
                topBarControls
            }

            VStack(alignment: .leading, spacing: 12) {
                topBarTitle
                topBarControls
            }
        }
        .padding(14)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var topBarTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Macro")
                .font(.title2.weight(.bold))
            Text("Major events across US, HK / China, Japan, Europe, and Commodity / Crypto.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var topBarControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                calendarModePicker
                calendarStepControls
            }

            VStack(alignment: .leading, spacing: 8) {
                calendarModePicker
                calendarStepControls
            }
        }
    }

    private var calendarModePicker: some View {
        Picker("Calendar View", selection: $calendarMode) {
            ForEach(NJInvestmentCalendarMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: isCompactLayout ? 140 : 160)
    }

    private var calendarStepControls: some View {
        HStack(spacing: 8) {
            Button { stepCalendar(-1) } label: { Image(systemName: "chevron.left") }
            Text(calendarTitle)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: isCompactLayout ? 96 : 128)
            Button { stepCalendar(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
    }

    private var marketPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NJInvestmentMarket.allCases) { market in
                    Button {
                        selectedMarket = market
                        selectedSnapshotLineID = defaultSnapshotLineID(for: market)
                    } label: {
                        Label(market.rawValue, systemImage: market.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedMarket == market ? Color.accentColor.opacity(0.18) : Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var marketSnapshotStrip: some View {
        let metrics = snapshotMetrics(for: selectedMarket)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(snapshotTitle(for: selectedMarket), icon: "waveform.path.ecg.rectangle")
                Spacer()
                if selectedMarket != .all {
                    Button {
                        UIPasteboard.general.string = snapshotBackfillPrompt(for: selectedMarket)
                    } label: {
                        Label("Copy Backfill Ask", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if metrics.isEmpty {
                Text("Choose US, HK / China, Japan, Europe, or Commodity / Crypto to show the market snapshot.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                    ForEach(metrics) { metric in
                        Button {
                            selectedSnapshotLineID = metric.id
                        } label: {
                            snapshotMetricCard(metric)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedSnapshotLineID == metric.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var marketSnapshotLineView: some View {
        let points = snapshotLinePoints(for: selectedSnapshotLineID)
        let chartPoints = chartPoints(from: points)
        let yDomain = smartChartYDomain(for: chartPoints)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(snapshotLineTitle(for: selectedSnapshotLineID), icon: "chart.line.uptrend.xyaxis")
                Spacer()
                Text(chartPoints.isEmpty ? "No chart yet" : "\(chartPoints.count) points")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if chartPoints.isEmpty {
                Text("Click a market snapshot metric above. A chart appears after numeric daily backfills exist.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Chart(chartPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        if point.id == chartPoints.last?.id {
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(point.isDown ? Color.red : Color.green)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5))
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing)
                    }
                    .chartYScale(domain: yDomain)
                    .frame(height: 220)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let latest = chartPoints.last {
                        Text("Latest \(formattedChartValue(latest.value)) \(latest.change)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(latest.isDown ? Color.red : Color.green)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func smartChartYDomain(for points: [NJInvestmentChartPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        let range = maxValue - minValue
        if range == 0 {
            let baseline = max(abs(maxValue), 1)
            let padding = baseline * 0.01
            return (minValue - padding)...(maxValue + padding)
        }

        let padding = max(range * 0.12, max(abs(maxValue), abs(minValue), 1) * 0.002)
        return (minValue - padding)...(maxValue + padding)
    }

    private func chartPoints(from points: [NJInvestmentLinePoint]) -> [NJInvestmentChartPoint] {
        points.compactMap { point in
            guard let date = parseDateKey(point.dateKey),
                  let value = numericValue(from: point.value) else { return nil }
            return NJInvestmentChartPoint(
                id: point.id,
                date: date,
                value: value,
                change: point.change,
                isDown: point.isDown
            )
        }
        .sorted { $0.date < $1.date }
    }

    private func numericValue(from text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
        let pattern = #"[-+]?\d*\.?\d+"#
        guard let range = cleaned.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(cleaned[range])
    }

    private func formattedChartValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value >= 100 ? 1 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func snapshotMetricCard(_ metric: NJInvestmentSnapshotMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(.title3.weight(.bold))
            Text(metric.change)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(snapshotChangeColor(metric.change))
            Text(metric.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var macroSignalScorecard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Macro Dashboard Scorecard", icon: "gauge.with.dots.needle.67percent")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                ForEach(filteredMacroSignals) { signal in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(signal.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(signal.status)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(signalStatusColor(signal.status).opacity(0.16))
                                .foregroundStyle(signalStatusColor(signal.status))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(signal.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Next: \(signal.nextCatalyst)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func macroSignalLine(_ signal: NJInvestmentMacroSignal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(signal.title, systemImage: signal.market.symbolName)
                    .font(.headline)
                Spacer()
                Text(signal.status)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(signalStatusColor(signal.status).opacity(0.16))
                    .foregroundStyle(signalStatusColor(signal.status))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(signal.note)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Next catalyst: \(signal.nextCatalyst)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var outlookStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Weekly Observations", icon: "scope")
            ForEach(filteredObservations) { observation in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(observation.title)
                            .font(.headline)
                        Spacer()
                        Text(observation.status)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(observation.thesis)
                        .font(.subheadline)
                    HStack(alignment: .top, spacing: 12) {
                        outlookMicroBlock("Confirm", observation.confirm)
                        outlookMicroBlock("Invalidate", observation.invalidate)
                    }
                    HStack {
                        Label(observation.market.rawValue, systemImage: observation.market.symbolName)
                        Text(observation.timeframe)
                        Text("Confidence: \(observation.confidence)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var macroCalendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    sectionHeader("Major Market Calendar", icon: "calendar")
                    Spacer()
                    marketPicker
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Major Market Calendar", icon: "calendar")
                    marketPicker
                }
            }

            if isCompactLayout {
                compactCalendarAgenda
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(calendarCells, id: \.key) { cell in
                        dayCell(cell)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var compactCalendarAgenda: some View {
        let rows = calendarCells
            .filter { $0.day != nil }
            .map { cell -> NJInvestmentCompactCalendarRow in
                NJInvestmentCompactCalendarRow(
                    id: cell.key,
                    cell: cell,
                    events: filteredEvents(on: cell.key),
                    snapshots: snapshotLines(for: cell.key)
                )
            }
            .filter { !$0.events.isEmpty || !$0.snapshots.isEmpty || $0.cell.isToday }

        return VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text("No tracked macro events in this view.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(rows) { row in
                    compactCalendarRow(row.cell, events: row.events, snapshots: row.snapshots)
                }
            }
        }
    }

    private func compactCalendarRow(
        _ cell: (key: String, day: Int?, isToday: Bool),
        events: [NJFinanceMacroEvent],
        snapshots: [(text: String, isDown: Bool)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(compactCalendarDateTitle(cell.key))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(cell.isToday ? Color.accentColor : Color.primary)
                Spacer()
                if !events.isEmpty {
                    Text("\(events.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
            }

            ForEach(events, id: \.eventID) { event in
                Button {
                    selectedEvent = event
                } label: {
                    Text(event.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(eventColor(event).opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            if !snapshots.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(snapshots.prefix(6), id: \.text) { line in
                        Text(line.text)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(line.isDown ? Color.red : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func compactCalendarDateTitle(_ key: String) -> String {
        guard let date = parseDateKey(key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, EEE"
        return formatter.string(from: date)
    }

    private var marketChecklistGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Macro Tracking Map", icon: "checklist")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(filteredChecklists) { checklist in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(checklist.title, systemImage: checklist.market.symbolName)
                            .font(.headline)
                        ForEach(checklist.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle")
                                    .font(.system(size: 8, weight: .semibold))
                                    .padding(.top, 5)
                                Text(item)
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                    .padding(14)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline.weight(.semibold))
    }

    private func outlookMicroBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func dayCell(_ cell: (key: String, day: Int?, isToday: Bool)) -> some View {
        let events = filteredEvents(on: cell.key)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(cell.day.map(String.init) ?? "")
                    .font(.caption.weight(cell.isToday ? .bold : .regular))
                    .foregroundStyle(cell.isToday ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
                if !events.isEmpty {
                    Text("\(events.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
            }
            ForEach(events.prefix(3), id: \.eventID) { event in
                Button {
                    selectedEvent = event
                } label: {
                    Text(event.title)
                        .font(.caption2.weight(selectedEvent?.eventID == event.eventID ? .semibold : .regular))
                        .lineLimit(2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(eventColor(event).opacity(selectedEvent?.eventID == event.eventID ? 0.26 : 0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            if events.count > 3 {
                Text("+\(events.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshotLines(for: cell.key), id: \.text) { line in
                Text(line.text)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(line.isDown ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 112, alignment: .topLeading)
        .padding(8)
        .background(cell.day == nil ? Color.clear : Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func snapshotLines(for cellDateKey: String) -> [(text: String, isDown: Bool)] {
        let snapshotEvents = (eventsByDate[cellDateKey] ?? [])
            .filter { $0.category == "market_snapshot" && (selectedMarket == .all || selectedMarket.matches(region: $0.region)) }
            .sorted { $0.title < $1.title }
        if !snapshotEvents.isEmpty {
            return snapshotEvents.map { event in
                let title = normalizedMarketSnapshotTitle(event.title)
                return (title, event.impact == "down" || title.contains(" -"))
            }
        }

        return []
    }

    private func eventResearchPanel(_ event: NJFinanceMacroEvent, showsCloseButton: Bool = true) -> some View {
        let research = eventResearch(for: event)
        let prompt = researchPrompt(for: event, research: research)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(event.title, systemImage: "doc.text.magnifyingglass")
                        .font(.headline.weight(.semibold))
                    Text("\(event.dateKey)  \(event.timeText)  \(event.region)  \(event.impact.capitalized) impact")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if showsCloseButton {
                    Button { selectedEvent = nil } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Research Ask")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(prompt)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    UIPasteboard.general.string = prompt
                } label: {
                    Label("Copy Research Prompt", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                researchBlock("Research Output", research.expectedValue, color: .blue)
                researchBlock("Impact Test", research.impact, color: eventColor(event))
                researchBlock("Data To Pull", research.researchSteps, color: .purple)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Source / Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(event.notes.isEmpty ? event.source : "\(event.source): \(event.notes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func researchPrompt(
        for event: NJFinanceMacroEvent,
        research: (summary: String, expectedValue: String, impact: String, researchSteps: String)
    ) -> String {
        """
        Research this macro event for my Investment Module.

        Event: \(event.title)
        Date/time: \(event.dateKey) \(event.timeText)
        Market/region: \(event.region)
        Category: \(event.category)
        Impact level: \(event.impact)
        Source context: \(event.notes.isEmpty ? event.source : event.notes)

        Please browse current primary/reliable sources and write a concise research note with:
        1. What this event is and why it matters now.
        2. Consensus / expected value, prior value, and key components to watch.
        3. Bullish, bearish, and neutral market-impact scenarios.
        4. Specific impact on my current macro thesis: ATH can hold into Nvidia, but June convergence may create pullback risk.
        5. Cross-market read-through for US equities, rates, USD/JPY or RMB/HKD where relevant, credit, and crypto risk appetite.
        6. A pre-event checklist and a post-event verdict template.

        Initial research angle: \(research.summary)
        Data to pull: \(research.researchSteps)
        """
    }

    private func snapshotMetrics(for market: NJInvestmentMarket) -> [NJInvestmentSnapshotMetric] {
        switch market {
        case .us:
            return [
                NJInvestmentSnapshotMetric(id: "spx", title: "S&P 500", value: "7,173.91", change: "Up +0.12% (+8.83 pts)", detail: "Last verified close: Apr 27, 2026 US session. Store on Apr 27 even when the heartbeat runs Tuesday morning in Asia."),
                NJInvestmentSnapshotMetric(id: "us10y", title: "US 10Y Treasury yield", value: "4.30%", change: "Approx -1 bp vs prior 4.31%", detail: "Yield level, not percent change. Do not store as 0.43%. Source: YCharts / Treasury-yield snapshots."),
                NJInvestmentSnapshotMetric(id: "vix", title: "VIX", value: "18.71", change: "-0.60 pts / -3.11%", detail: "Last official Cboe history row: Apr 24, 2026. Apr 27 official close is still pending in Cboe's public CSV; refresh as soon as the file advances.")
            ]
        case .chinaHK:
            return [
                NJInvestmentSnapshotMetric(id: "hkse", title: "HKSE / Hang Seng", value: "25,978", change: "Up +0.24% (+62 pts)", detail: "Latest verified close found: Apr 24/25, 2026. Source: BusinessToday Malaysia."),
                NJInvestmentSnapshotMetric(id: "shanghai-a", title: "Shanghai A", value: "4,162.88", change: "Up +0.39%", detail: "Latest verified close found: Apr 24, 2026. Source: TS2 China economy market recap.")
            ]
        case .japan:
            return [
                NJInvestmentSnapshotMetric(id: "tokyo", title: "Tokyo Exchange", value: "Nikkei 225: 60,537.36", change: "Record close", detail: "Latest verified close found: Apr 27, 2026. Source: Nikkei 225 closing milestone."),
                NJInvestmentSnapshotMetric(id: "jgb", title: "JGB", value: "10Y JGB: 2.44%", change: "Up to 1-week high", detail: "Latest verified level found: Apr 24, 2026. Source: Trading Economics.")
            ]
        case .europe:
            return [
                NJInvestmentSnapshotMetric(id: "stoxx600", title: "STOXX Europe 600", value: "608.84", change: "-0.30%", detail: "Apr 27, 2026 close. Source: Yahoo Finance chart endpoint."),
                NJInvestmentSnapshotMetric(id: "stoxx50", title: "Euro Stoxx 50", value: "5,860.32", change: "-0.39%", detail: "Apr 27, 2026 close. Source: Yahoo Finance chart endpoint."),
                NJInvestmentSnapshotMetric(id: "bund10y", title: "Germany 10Y Bund", value: "3.036%", change: "+2.92 bps", detail: "Apr 27, 2026 close. Source: Investing.com Germany 10-Year Bond Yield historical data."),
                NJInvestmentSnapshotMetric(id: "uk10y", title: "UK 10Y Gilt", value: "5.00%", change: "About +8 bps intraday", detail: "Apr 27, 2026 intraday Europe bond snapshot. Keep as intraday until a clean final close is captured."),
                NJInvestmentSnapshotMetric(id: "eurusd", title: "EUR/USD", value: "1.1749", change: "ECB reference", detail: "Apr 27, 2026 ECB reference rate. Yahoo latest Apr 28 quote was 1.1718.")
            ]
        case .crypto:
            return [
                NJInvestmentSnapshotMetric(id: "bitcoin", title: "Bitcoin", value: "~$79,457", change: "Up +2.50%", detail: "Indicative Apr 27, 2026 crypto snapshot; needs heartbeat refresh."),
                NJInvestmentSnapshotMetric(id: "ethereum", title: "ETH", value: "$2,393.98", change: "Up +3.56%", detail: "Indicative Apr 27, 2026 quote. Source: CoinCodex."),
                NJInvestmentSnapshotMetric(id: "brent", title: "Brent Oil", value: "Above $106/bbl", change: "Up >1%", detail: "Indicative Apr 27, 2026 early quote. Source: Goodreturns live market note."),
                NJInvestmentSnapshotMetric(id: "wti", title: "WTI Oil", value: "Above $95/bbl", change: "Up >1%", detail: "Indicative Apr 27, 2026 early quote. Source: Goodreturns live market note."),
                NJInvestmentSnapshotMetric(id: "gold", title: "Gold", value: "~$4,754/oz", change: "Near highs", detail: "Indicative Apr 22, 2026 spot reference from market analysis; needs heartbeat refresh."),
                NJInvestmentSnapshotMetric(id: "silver", title: "Silver", value: ">$66/oz", change: "Active Apr 27 band", detail: "Indicative front-month futures band from Apr 27 prediction-market listing; needs heartbeat refresh.")
            ]
        case .all:
            return []
        }
    }

    private func snapshotTitle(for market: NJInvestmentMarket) -> String {
        switch market {
        case .us: return "US Market Snapshot"
        case .chinaHK: return "HK / China Market Snapshot"
        case .japan: return "Japan Market Snapshot"
        case .europe: return "Europe Market Snapshot"
        case .crypto: return "Commodity / Crypto Snapshot"
        case .all: return "Market Snapshot"
        }
    }

    private func defaultSnapshotLineID(for market: NJInvestmentMarket) -> String {
        switch market {
        case .us, .all: return "spx"
        case .chinaHK: return "hkse"
        case .japan: return "tokyo"
        case .europe: return "stoxx600"
        case .crypto: return "bitcoin"
        }
    }

    private func snapshotLineTitle(for lineID: String) -> String {
        switch lineID {
        case "spx": return "S&P 500 Line"
        case "us10y": return "US 10Y Line"
        case "vix": return "VIX Line"
        case "hkse": return "Hang Seng Line"
        case "shanghai-a": return "Shanghai A Line"
        case "tokyo": return "Tokyo Equity Line"
        case "jgb": return "JGB Line"
        case "stoxx600": return "STOXX Europe 600 Line"
        case "stoxx50": return "Euro Stoxx 50 Line"
        case "bund10y": return "10Y Bund Line"
        case "uk10y": return "UK 10Y Gilt Line"
        case "eurusd": return "EUR/USD Line"
        case "bitcoin": return "Bitcoin Line"
        case "ethereum": return "ETH Line"
        case "brent": return "Brent Line"
        case "wti": return "WTI Line"
        case "gold": return "Gold Line"
        case "silver": return "Silver Line"
        default: return "Market Line"
        }
    }

    private func snapshotLinePoints(for lineID: String) -> [NJInvestmentLinePoint] {
        let eventPrefix: String
        switch lineID {
        case "spx":
            eventPrefix = "market_snapshot.us.spx."
        case "us10y":
            eventPrefix = "market_snapshot.us.us10y."
        case "vix":
            eventPrefix = "market_snapshot.us.vix."
        case "hkse":
            eventPrefix = "market_snapshot.hk_china.hang_seng."
        case "shanghai-a":
            eventPrefix = "market_snapshot.hk_china.shanghai_a."
        case "tokyo":
            eventPrefix = "market_snapshot.japan.nikkei."
        case "jgb":
            eventPrefix = "market_snapshot.japan.jgb10y."
        case "stoxx600":
            eventPrefix = "market_snapshot.europe.stoxx600."
        case "stoxx50":
            eventPrefix = "market_snapshot.europe.stoxx50."
        case "bund10y":
            eventPrefix = "market_snapshot.europe.bund10y."
        case "uk10y":
            eventPrefix = "market_snapshot.europe.uk10y."
        case "eurusd":
            eventPrefix = "market_snapshot.europe.eurusd."
        case "bitcoin":
            eventPrefix = "market_snapshot.commodity_crypto.btc."
        case "ethereum":
            eventPrefix = "market_snapshot.commodity_crypto.eth."
        case "brent":
            eventPrefix = "market_snapshot.commodity_crypto.brent."
        case "wti":
            eventPrefix = "market_snapshot.commodity_crypto.wti."
        case "gold":
            eventPrefix = "market_snapshot.commodity_crypto.gold."
        case "silver":
            eventPrefix = "market_snapshot.commodity_crypto.silver."
        default:
            return []
        }

        let storedPoints = store.notes.listFinanceMacroEvents(startKey: "2026-01-01", endKey: dateKey(Date()))
            .filter { $0.eventID.hasPrefix(eventPrefix) }
            .sorted { $0.dateKey > $1.dateKey }
            .compactMap { event -> NJInvestmentLinePoint? in
                let parts = event.title.split(separator: " ")
                guard parts.count >= 3 else { return nil }
                let normalizedTitle = normalizedMarketSnapshotTitle(event.title)
                let normalizedParts = normalizedTitle.split(separator: " ")
                guard normalizedParts.count >= 3 else { return nil }
                let value = String(normalizedParts[1])
                let change = normalizedParts.dropFirst(2).joined(separator: " ")
                return NJInvestmentLinePoint(
                    id: event.eventID,
                    dateKey: event.dateKey,
                    value: value,
                    change: change,
                    isDown: event.impact == "down" || change.hasPrefix("-")
                )
            }
        if !storedPoints.isEmpty { return storedPoints }

        guard let metric = snapshotMetrics(for: marketForSnapshotLineID(lineID)).first(where: { $0.id == lineID }) else {
            return []
        }
        return [
            NJInvestmentLinePoint(
                id: "static.\(lineID).\(dateKey(Date()))",
                dateKey: dateKey(Date()),
                value: metric.value,
                change: metric.change,
                isDown: snapshotChangeColor(metric.change) == .red
            )
        ]
    }

    private func normalizedMarketSnapshotTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("US10Y ") else { return trimmed }

        let parts = trimmed.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return trimmed }
        let rawValue = parts[1]
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(rawValue) else { return trimmed }

        let corrected = value < 1 ? value * 10 : value
        let rest = parts.count > 2 ? " \(parts[2])" : ""
        return String(format: "US10Y %.2f%%%@", corrected, rest)
    }

    private func marketForSnapshotLineID(_ lineID: String) -> NJInvestmentMarket {
        switch lineID {
        case "spx", "us10y", "vix": return .us
        case "hkse", "shanghai-a": return .chinaHK
        case "tokyo", "jgb": return .japan
        case "stoxx600", "stoxx50", "bund10y", "uk10y", "eurusd": return .europe
        case "bitcoin", "ethereum", "brent", "wti", "gold", "silver": return .crypto
        default: return selectedMarket
        }
    }

    private func snapshotChangeColor(_ change: String) -> Color {
        let value = change.lowercased()
        if value.contains("-") || value.contains("down") { return .red }
        if value.contains("+") || value.contains("up") { return .green }
        return .secondary
    }

    private func signalStatusColor(_ status: String) -> Color {
        let value = status.lowercased()
        if value.contains("red") || value.contains("stress") || value.contains("tight") { return .red }
        if value.contains("yellow") || value.contains("watch") || value.contains("mixed") { return .orange }
        if value.contains("green") || value.contains("supportive") || value.contains("calm") { return .green }
        return .secondary
    }

    private func snapshotBackfillPrompt(for market: NJInvestmentMarket) -> String {
        switch market {
        case .us:
            return """
            Backfill today's US market snapshot for the Investment Macro module.

            Pull current/last-close values and daily change:
            1. S&P 500: index level and up/down percentage. If down, mark red.
            2. US 10Y Treasury yield: yield level and daily move in basis points.
            3. VIX: index level and daily point / percent move.

            Use Cboe VIX historical daily prices as the primary VIX source when available: https://cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv
            If the target US close is not yet present in the Cboe file, show the latest official Cboe close and explicitly mark the target close as stale/pending instead of leaving VIX blank. Return concise values ready to paste into the module.
            """
        case .chinaHK:
            return """
            Backfill today's HK / China market snapshot for the Investment Macro module.

            Pull current/last-close values and daily change:
            1. HKSE / Hang Seng: index level and up/down percentage. If down, mark red.
            2. Shanghai A: index level and up/down percentage. If down, mark red.

            Use reliable market sources, note timestamp and whether each market is open, closed, or delayed. Return concise values ready to paste into the module.
            """
        case .japan:
            return """
            Backfill today's Japan market snapshot for the Investment Macro module.

            Pull current/last-close values and daily change:
            1. Tokyo Exchange: equity index level and up/down percentage. If down, mark red.
            2. JGB: 10Y JGB yield level and daily move in basis points.

            Use reliable market sources, note timestamp and whether the market is open, closed, or delayed. Return concise values ready to paste into the module.
            """
        case .europe:
            return """
            Backfill today's Europe market snapshot for the Investment Macro module.

            Pull current/last-close values and daily change:
            1. STOXX Europe 600: broad Europe stock index level and up/down percentage. If down, mark red.
            2. Euro Stoxx 50: eurozone blue-chip index level and up/down percentage. If down, mark red.
            3. German 10Y Bund yield: yield level and daily move in basis points.
            4. UK 10Y Gilt yield: yield level and daily move in basis points.
            5. EUR/USD: spot level and up/down percentage.

            Use reliable market sources, note timestamp and whether the market is open, closed, or delayed. Return concise values ready to paste into the module.
            """
        case .crypto:
            return """
            Backfill today's Commodity / Crypto market snapshot for the Investment Macro module.

            Pull current values and 24h change:
            1. Bitcoin: spot price and up/down percentage. If down, mark red.
            2. ETH: spot price and up/down percentage. If down, mark red.
            3. Brent oil: front-month or spot price and up/down percentage.
            4. WTI oil: front-month or spot price and up/down percentage.
            5. Gold: XAU spot or front-month futures and up/down percentage.
            6. Silver: XAG spot or front-month futures and up/down percentage.

            Use reliable market sources, note timestamp, and mention if prices are from spot index, exchange quote, futures, or aggregated feed. Return concise values ready to paste into the module.
            """
        case .all:
            return "Choose US, HK / China, Japan, Europe, or Commodity / Crypto before backfilling a market snapshot."
        }
    }

    private func researchBlock(_ title: String, _ body: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(12)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var filteredObservations: [NJInvestmentObservation] {
        observations.filter { selectedMarket == .all || $0.market == selectedMarket }
    }

    private var filteredTrades: [NJInvestmentTradeThesis] {
        tradeTheses.filter { selectedMarket == .all || $0.market == selectedMarket }
    }

    private var filteredChecklists: [NJInvestmentMarketChecklist] {
        marketChecklists.filter { selectedMarket == .all || $0.market == selectedMarket }
    }

    private var filteredMacroSignals: [NJInvestmentMacroSignal] {
        macroSignals.filter { selectedMarket == .all || $0.market == selectedMarket }
    }

    private func filteredEvents(on dateKey: String) -> [NJFinanceMacroEvent] {
        (eventsByDate[dateKey] ?? [])
            .filter { selectedMarket.matches(region: $0.region) }
            .filter { $0.category != "market_snapshot" }
            .sorted { ($0.impact, $0.timeText, $0.title) < ($1.impact, $1.timeText, $1.title) }
    }

    private func reloadEvents() {
        let range = visibleDateRange
        let start = range.start
        let end = range.end
        let rows = store.notes.listFinanceMacroEvents(startKey: dateKey(start), endKey: dateKey(end))
        eventsByDate = Dictionary(grouping: rows, by: { $0.dateKey })
    }

    private func stepCalendar(_ delta: Int) {
        switch calendarMode {
        case .week:
            focusedMonth = calendar.date(byAdding: .day, value: delta * 7, to: focusedMonth) ?? focusedMonth
        case .month:
            focusedMonth = calendar.date(byAdding: .month, value: delta, to: focusedMonth) ?? focusedMonth
        }
    }

    private var calendarTitle: String {
        switch calendarMode {
        case .week:
            let range = visibleDateRange
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
        case .month:
            return monthTitle
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: focusedMonth)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var calendarCells: [(key: String, day: Int?, isToday: Bool)] {
        switch calendarMode {
        case .week:
            return weekCells
        case .month:
            return monthCells
        }
    }

    private var visibleDateRange: (start: Date, end: Date) {
        switch calendarMode {
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: focusedMonth)?.start ?? focusedMonth
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? focusedMonth
            return (start, end)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: focusedMonth)
            let start = interval?.start ?? focusedMonth
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? focusedMonth
            return (start, end)
        }
    }

    private var weekCells: [(key: String, day: Int?, isToday: Bool)] {
        let start = visibleDateRange.start
        let todayKey = dateKey(Date())
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = dateKey(date)
            return (key, calendar.component(.day, from: date), key == todayKey)
        }
    }

    private var monthCells: [(key: String, day: Int?, isToday: Bool)] {
        guard let interval = calendar.dateInterval(of: .month, for: focusedMonth) else { return [] }
        let first = interval.start
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let todayKey = dateKey(Date())
        var cells: [(String, Int?, Bool)] = []
        for i in 0..<leading {
            cells.append(("blank-\(i)", nil, false))
        }
        for day in 1...days {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: first) else { continue }
            let key = dateKey(date)
            cells.append((key, day, key == todayKey))
        }
        while cells.count % 7 != 0 {
            cells.append(("blank-tail-\(cells.count)", nil, false))
        }
        return cells
    }

    private func eventResearch(for event: NJFinanceMacroEvent) -> (summary: String, expectedValue: String, impact: String, researchSteps: String) {
        let title = event.title.lowercased()
        let category = event.category.lowercased()
        if category.contains("inflation") || title.contains("cpi") || title.contains("ppi") || title.contains("pce") {
            return (
                "Inflation prints decide whether central banks can stay patient or need to lean hawkish. For your June-pullback thesis, hot inflation raises the chance that duration and high-multiple equities get pressured.",
                "Compare actual vs consensus, prior revision, core trend, services inflation, and 3-month annualized momentum.",
                "Hot: yields up, USD/JPY pressure up, growth stocks vulnerable. Cool: rate-cut or pause narrative improves and risk assets can extend.",
                "Pull consensus before release, record actual-surprise, then write a same-day note on yields, FX, index breadth, and Mag 7 reaction."
            )
        }
        if category.contains("consumer") || title.contains("retail") || title.contains("sentiment") {
            return (
                "Consumer data tests whether demand is still carrying the cycle or quietly weakening under higher rates and debt load.",
                "Focus on control group sales, real spending direction, revisions, discretionary categories, and consumer-credit stress context.",
                "Strong demand can support earnings but also keep yields high. Weak demand helps bonds but can hurt cyclicals and credit-sensitive names.",
                "Track actual vs consensus, revisions, category mix, card/delinquency context, and the market reaction in retailers, banks, and long-duration tech."
            )
        }
        if category.contains("labor") || title.contains("employment") || title.contains("payroll") {
            return (
                "Employment is the cleanest read on whether the US economy is slowing enough for the Fed or still too tight for risk assets.",
                "Watch payrolls, unemployment, participation, wage growth, hours worked, and prior-month revisions.",
                "Hot labor can pressure bonds and valuation. Weak labor can first help rates, then hurt equities if recession risk takes over.",
                "Record headline, wage trend, revisions, 2Y yield move, USD move, and whether equity breadth improves or narrows."
            )
        }
        if category.contains("central") || title.contains("fed") || title.contains("boj") {
            return (
                "Central-bank events anchor the macro path. They matter most when the market is priced for one policy story and guidance challenges it.",
                "Expected value comes from the gap between priced policy path and actual statement, dots, press conference, or successor guidance.",
                "Hawkish surprise pressures duration, yen carry, and high-beta equity. Dovish surprise supports liquidity and can extend ATH behavior.",
                "Before event: note market-implied rates. After event: record guidance shift, yield curve move, FX reaction, and leadership change."
            )
        }
        if category.contains("debt") || title.contains("treasury") || title.contains("auction") {
            return (
                "Debt supply matters because weak auctions can lift term premium and tighten financial conditions even without a Fed move.",
                "Watch auction size, bid-to-cover, tail, indirect demand, dealer take-down, and refunding composition across maturities.",
                "Weak demand: long yields rise and equity multiples compress. Strong demand: term-premium concern fades and risk can stabilize.",
                "Record announced supply, auction response, 10Y/30Y yield move, curve shape, and equity reaction in banks, housing, and Mag 7."
            )
        }
        if category.contains("earnings") || title.contains("nvidia") {
            return (
                "This is a direct test of the AI leadership thesis. Nvidia can decide whether ATH behavior broadens or becomes a sell-the-news moment.",
                "Expected value comes from revenue guide, data-center growth, gross margin, supply constraints, capex commentary, and hyperscaler demand.",
                "Beat-and-raise can extend AI leadership. Good-but-not-good-enough can trigger the pullback you are watching for before June.",
                "Compare results to whisper expectations, track NVDA after-hours move, semis breadth, Mag 7 sympathy, and index futures."
            )
        }
        if category.contains("crypto") {
            return (
                "Crypto is mostly a liquidity, positioning, ETF-flow, regulation, and headline tape. It can be an early risk-appetite signal.",
                "Expected value comes from whether flows and regulatory headlines confirm or reject the current trend.",
                "Positive flow/liquidity news supports high beta. Regulatory or exchange stress can spill into broader speculative risk.",
                "Track BTC/ETH/SOL trend, ETF flows, stablecoin supply, exchange headlines, funding, and open interest concentration."
            )
        }
        if category.contains("growth") {
            return (
                "Growth data tests whether the regional macro story is accelerating, slowing, or policy-supported but still fragile.",
                "Watch actual vs consensus, revision direction, retail sales, industrial production, property, and fixed asset investment.",
                "Upside supports local equity beta and commodities. Downside raises stimulus hopes but can hurt earnings confidence.",
                "Record the surprise, policy response, FX move, equity-sector leadership, and whether China/HK beta confirms."
            )
        }
        if category.contains("market_close") {
            return (
                "This is a market-closure or shortened-session marker. It matters because liquidity, settlement timing, cross-market lead-lag, and gap risk can change around closed exchanges.",
                "Check which cash, futures, options, bond, and after-hours sessions are closed or shortened, plus whether adjacent markets remain open.",
                "Closed markets can suppress local price discovery and shift reaction into futures, ADRs, ETFs, FX, or the next reopening session.",
                "Research whether major macro/news events occur while the market is closed, then note reopen-gap risk and which proxy markets are trading."
            )
        }
        return (
            "This event belongs in the macro calendar because it can shift rates, FX, liquidity, earnings expectations, or risk appetite.",
            "Compare actual outcome against consensus and your prior thesis.",
            "Impact depends on surprise direction and whether equities, yields, credit, and FX all confirm the same message.",
            "Before event: write expectation. After event: record actual, surprise, first market reaction, and whether it changes the weekly thesis."
        )
    }

    private func dateKey(_ date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private func parseDateKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private func eventColor(_ event: NJFinanceMacroEvent) -> Color {
        switch event.category.lowercased() {
        case let value where value.contains("market_close"): return .gray
        case let value where value.contains("inflation"): return .red
        case let value where value.contains("labor"): return .blue
        case let value where value.contains("central"): return .purple
        case let value where value.contains("auction") || value.contains("debt"): return .orange
        default: return .green
        }
    }

    private var observations: [NJInvestmentObservation] {
        [
            NJInvestmentObservation(
                id: "ath-nvidia-june-convergence",
                title: "ATH Hold, Then Nvidia / June Pullback Risk",
                market: .us,
                timeframe: "Now through June",
                confidence: "Medium",
                thesis: "Market can hold near all-time highs into Nvidia, then become vulnerable as June converges around Fed-chair uncertainty, BOJ rate pressure, and stretched AI positioning.",
                confirm: "Index breadth weakens, AI leaders fail good news, yields or yen pressure rise into June.",
                invalidate: "Nvidia broadens participation, credit stays calm, Fed path remains clear, BOJ avoids a hawkish surprise.",
                status: "Active"
            ),
            NJInvestmentObservation(
                id: "japan-rate-trigger",
                title: "Japan Is The Cross-Market Trigger",
                market: .japan,
                timeframe: "1-3 months",
                confidence: "Medium",
                thesis: "BOJ normalization matters because yen carry, JGB yields, and global risk appetite are linked. A fast repricing could pressure US duration and equities.",
                confirm: "JPY strengthens sharply, JGB yields climb, global high-beta sells off together.",
                invalidate: "BOJ delays hikes and yen remains an orderly funding currency.",
                status: "Watching"
            )
        ]
    }

    private var tradeTheses: [NJInvestmentTradeThesis] {
        [
            NJInvestmentTradeThesis(id: "dream-girl-mag7", title: "Dream Girl Trade / Mag 7", market: .us, status: "Active", premise: "Mega-cap quality is almost always there for the market. If the group falls too far without a thesis break, buyers pull it back into leadership.", watch: "NVDA, MSFT, AAPL, AMZN, META, GOOGL, TSLA relative strength.", invalidation: "Earnings revisions roll over or AI capex becomes a margin problem."),
            NJInvestmentTradeThesis(id: "saas-overshoot", title: "SaaS Overshoot", market: .us, status: "Watchlist", premise: "High-quality SaaS can overshoot downside when duration and growth sentiment compress, creating rebound candidates like DDOG after capitulation.", watch: "DDOG plus peers with strong retention, improving FCF, and clean guidance.", invalidation: "Enterprise spend slows broadly or net retention degradation accelerates."),
            NJInvestmentTradeThesis(id: "trump-xi", title: "Trump-Xi Trade", market: .chinaHK, status: "Scenario", premise: "Policy headlines and negotiation posture can drive sharp China/HK beta moves before fundamentals confirm.", watch: "Tariff language, export controls, CNH, Hang Seng Tech, southbound flow.", invalidation: "Talks harden into sustained escalation with no policy offset."),
            NJInvestmentTradeThesis(id: "china-ai", title: "China AI Trade", market: .chinaHK, status: "Watching", premise: "China AI names can re-rate when policy support, model progress, and local substitution line up.", watch: "Cloud capex, domestic chip constraints, model releases, platform monetization.", invalidation: "Compute bottlenecks or regulation prevents revenue conversion."),
            NJInvestmentTradeThesis(id: "commodity-crypto-major-news", title: "Commodity / Crypto News Tape", market: .crypto, status: "Watching", premise: "Crypto and commodities trade liquidity, inflation impulse, geopolitical supply shock, ETF flow, and regulation more than traditional earnings cadence.", watch: "BTC, ETH, Brent, WTI, gold, silver, ETF flows, major legal or exchange news.", invalidation: "Liquidity contracts while inflation hedges fail to respond to macro stress.")
        ]
    }

    private var watchListRows: [NJInvestmentWatchRow] {
        [
            NJInvestmentWatchRow(id: "watch-ddog", symbol: "DDOG", name: "Datadog", monitorDate: "2026-04-24", initialPrice: "$129.48", week52High: "$201.69", week52Low: "$98.01", todayPrice: "$132.66", percentChange: "+2.46%"),
            NJInvestmentWatchRow(id: "watch-mdb", symbol: "MDB", name: "MongoDB", monitorDate: "2026-04-24", initialPrice: "$253.59", week52High: "$444.72", week52Low: "$167.19", todayPrice: "$264.38", percentChange: "+4.25%"),
            NJInvestmentWatchRow(id: "watch-team", symbol: "TEAM", name: "Atlassian", monitorDate: "2026-04-24", initialPrice: "$71.55", week52High: "$242.00", week52Low: "$56.01", todayPrice: "$69.22", percentChange: "-3.26%"),
            NJInvestmentWatchRow(id: "watch-net", symbol: "NET", name: "Cloudflare", monitorDate: "2026-04-24", initialPrice: "$207.07", week52High: "$260.00", week52Low: "$117.07", todayPrice: "$212.36", percentChange: "+2.55%"),
            NJInvestmentWatchRow(id: "watch-snow", symbol: "SNOW", name: "Snowflake", monitorDate: "2026-04-24", initialPrice: "$140.32", week52High: "$280.67", week52Low: "$118.30", todayPrice: "$144.25", percentChange: "+2.80%")
        ]
    }

    private var chinaAIWatchListRows: [NJInvestmentWatchRow] {
        [
            NJInvestmentWatchRow(id: "chinaai-bidu", symbol: "BIDU", name: "Baidu", monitorDate: "2026-04-24", initialPrice: "$128.71", week52High: "$165.30", week52Low: "$81.17", todayPrice: "$128.01", percentChange: "-0.54%"),
            NJInvestmentWatchRow(id: "chinaai-baba", symbol: "BABA", name: "Alibaba", monitorDate: "2026-04-24", initialPrice: "$135.82", week52High: "$192.67", week52Low: "$103.71", todayPrice: "$132.52", percentChange: "-2.43%"),
            NJInvestmentWatchRow(id: "chinaai-tencent", symbol: "0700 HK", name: "Tencent", monitorDate: "2026-04-24", initialPrice: "HK$493.40", week52High: "HK$683.00", week52Low: "HK$469.00", todayPrice: "HK$478.60", percentChange: "-3.00%"),
            NJInvestmentWatchRow(id: "chinaai-iflytek", symbol: "002230 CN", name: "iFlytek", monitorDate: "2026-04-24", initialPrice: "CNY49.07", week52High: "CNY67.50", week52Low: "CNY44.98", todayPrice: "CNY49.81", percentChange: "+1.51%"),
            NJInvestmentWatchRow(id: "chinaai-smic", symbol: "0981 HK", name: "SMIC", monitorDate: "2026-04-24", initialPrice: "HK$64.30", week52High: "HK$93.50", week52Low: "HK$38.65", todayPrice: "HK$68.25", percentChange: "+6.14%"),
            NJInvestmentWatchRow(id: "chinaai-cambricon", symbol: "688256 CN", name: "Cambricon", monitorDate: "2026-04-24", initialPrice: "CNY1,352.50", week52High: "CNY1,595.88", week52Low: "CNY520.67", todayPrice: "CNY1,356.72", percentChange: "+0.31%"),
            NJInvestmentWatchRow(id: "chinaai-jcet", symbol: "600584 CN", name: "JCET Group", monitorDate: "2026-04-24", initialPrice: "CNY44.89", week52High: "CNY54.63", week52Low: "CNY31.20", todayPrice: "CNY46.32", percentChange: "+3.19%"),
            NJInvestmentWatchRow(id: "chinaai-tongfu", symbol: "002156 CN", name: "Tongfu Microelectronics", monitorDate: "2026-04-24", initialPrice: "CNY48.42", week52High: "CNY59.20", week52Low: "CNY22.90", todayPrice: "CNY51.20", percentChange: "+5.74%"),
            NJInvestmentWatchRow(id: "chinaai-huatian", symbol: "002185 CN", name: "Huatian Technology", monitorDate: "2026-04-24", initialPrice: "CNY12.45", week52High: "CNY16.00", week52Low: "CNY8.60", todayPrice: "CNY12.89", percentChange: "+3.53%"),
            NJInvestmentWatchRow(id: "chinaai-usdcnh", symbol: "USD/CNH", name: "Offshore yuan FX", monitorDate: "2026-04-24", initialPrice: "6.82", week52High: "6.83", week52Low: "6.82", todayPrice: "6.82", percentChange: "n/a")
        ]
    }

    private var globalAIInfrastructureWatchListRows: [NJInvestmentWatchRow] {
        [
            NJInvestmentWatchRow(id: "globalai-fcx", symbol: "FCX", name: "Freeport-McMoRan", monitorDate: "2026-04-24", initialPrice: "$61.05", week52High: "$70.97", week52Low: "$34.45", todayPrice: "$60.57", percentChange: "-0.79%"),
            NJInvestmentWatchRow(id: "globalai-scco", symbol: "SCCO", name: "Southern Copper", monitorDate: "2026-04-24", initialPrice: "$180.43", week52High: "$223.89", week52Low: "$84.13", todayPrice: "$178.12", percentChange: "-1.28%"),
            NJInvestmentWatchRow(id: "globalai-zijin", symbol: "2899 HK", name: "Zijin Mining", monitorDate: "2026-04-24", initialPrice: "HK$36.80", week52High: "HK$46.98", week52Low: "HK$16.70", todayPrice: "HK$36.22", percentChange: "-1.58%"),
            NJInvestmentWatchRow(id: "globalai-nee", symbol: "NEE", name: "NextEra Energy", monitorDate: "2026-04-24", initialPrice: "$95.28", week52High: "$97.63", week52Low: "$63.88", todayPrice: "$94.83", percentChange: "-0.47%"),
            NJInvestmentWatchRow(id: "globalai-duk", symbol: "DUK", name: "Duke Energy", monitorDate: "2026-04-24", initialPrice: "$127.27", week52High: "$134.49", week52Low: "$111.22", todayPrice: "$127.09", percentChange: "-0.14%"),
            NJInvestmentWatchRow(id: "globalai-vst", symbol: "VST", name: "Vistra", monitorDate: "2026-04-24", initialPrice: "$164.35", week52High: "$219.82", week52Low: "$122.30", todayPrice: "$166.58", percentChange: "+1.36%"),
            NJInvestmentWatchRow(id: "globalai-etn", symbol: "ETN", name: "Eaton", monitorDate: "2026-04-24", initialPrice: "$423.92", week52High: "$432.34", week52Low: "$283.00", todayPrice: "$416.77", percentChange: "-1.69%"),
            NJInvestmentWatchRow(id: "globalai-su", symbol: "SU FP", name: "Schneider Electric", monitorDate: "2026-04-24", initialPrice: "EUR276.00", week52High: "EUR281.50", week52Low: "EUR199.30", todayPrice: "EUR276.00", percentChange: "+0.42%"),
            NJInvestmentWatchRow(id: "globalai-enr", symbol: "ENR GR", name: "Siemens Energy", monitorDate: "2026-04-24", initialPrice: "EUR187.62", week52High: "EUR191.66", week52Low: "EUR65.56", todayPrice: "EUR187.62", percentChange: "+2.64%"),
            NJInvestmentWatchRow(id: "globalai-hitachi", symbol: "6501 JP", name: "Hitachi", monitorDate: "2026-04-24", initialPrice: "JPY5,229", week52High: "JPY6,039", week52Low: "JPY3,516", todayPrice: "JPY5,356", percentChange: "+2.43%"),
            NJInvestmentWatchRow(id: "globalai-vrt", symbol: "VRT", name: "Vertiv", monitorDate: "2026-04-24", initialPrice: "$323.46", week52High: "$330.30", week52Low: "$80.51", todayPrice: "$322.43", percentChange: "-0.32%"),
            NJInvestmentWatchRow(id: "globalai-jci", symbol: "JCI", name: "Johnson Controls", monitorDate: "2026-04-24", initialPrice: "$141.92", week52High: "$146.49", week52Low: "$80.19", todayPrice: "$143.38", percentChange: "+1.03%"),
            NJInvestmentWatchRow(id: "globalai-tt", symbol: "TT", name: "Trane Technologies", monitorDate: "2026-04-24", initialPrice: "$486.42", week52High: "$493.69", week52Low: "$346.45", todayPrice: "$485.90", percentChange: "-0.11%")
        ]
    }

    private var kpiRows: [NJInvestmentKPIRow] {
        [
            NJInvestmentKPIRow(id: "dream-breadth", trade: "Dream Girl / Mag 7", kpi: "Mag 7 relative strength", target: "Holds vs S&P/QQQ", current: "Needs daily refresh", actionRule: "Go closer only when drawdown happens without leadership breakdown."),
            NJInvestmentKPIRow(id: "dream-nvda-earnings", trade: "Dream Girl / Mag 7", kpi: "NVDA earnings setup", target: "Guidance and capex story intact", current: "Next catalyst", actionRule: "Reduce confidence if guidance fails to support AI capex cycle."),
            NJInvestmentKPIRow(id: "saas-revisions", trade: "SaaS Overshoot", kpi: "Revenue / FCF revision trend", target: "Stable or improving", current: "Needs backfill", actionRule: "Enter only if price capitulates while estimates stop falling."),
            NJInvestmentKPIRow(id: "china-policy", trade: "China AI", kpi: "Policy + credit impulse", target: "Supportive liquidity / AI policy", current: "Watch", actionRule: "Avoid if policy headlines improve but CNH/property stress worsens."),
            NJInvestmentKPIRow(id: "trump-xi-fx", trade: "Trump-Xi", kpi: "USDCNH + tariff language", target: "CNH stable and rhetoric softer", current: "Needs daily refresh", actionRule: "Treat hardening rhetoric plus CNH weakness as invalidation.")
        ]
    }

    private var actualTradeRows: [NJInvestmentActualTradeRow] {
        [
            NJInvestmentActualTradeRow(id: "no-live-trade", trade: "No confirmed live trade", symbol: "-", position: "None recorded", entry: "-", thesisStatus: "Create a transaction card only after a real trade is confirmed.")
        ]
    }

    private var movementRows: [NJInvestmentMovementRow] {
        [
            NJInvestmentMovementRow(id: "movement-template", date: "Daily", symbol: "Watch list", move: "Needs refresh", read: "Heartbeat should record whether each watch symbol moved toward target, away from target, or invalidated the setup.", nextStep: "Create daily movement row"),
            NJInvestmentMovementRow(id: "nvda-template", date: "Daily", symbol: "NVDA", move: "Needs refresh", read: "Track whether NVDA supports ATH-hold thesis into earnings.", nextStep: "Compare with QQQ and SOXX"),
            NJInvestmentMovementRow(id: "ddog-template", date: "Daily", symbol: "DDOG", move: "Needs refresh", read: "Track whether downside is overshoot or thesis break.", nextStep: "Check SaaS basket and guidance news")
        ]
    }

    private var macroSignals: [NJInvestmentMacroSignal] {
        [
            NJInvestmentMacroSignal(id: "us-liquidity", market: .us, title: "US Liquidity", status: "Watch", note: "Fed balance sheet, QT pace, TGA, reverse repo, and bank reserves decide whether ATH conditions have enough fuel.", nextCatalyst: "Weekly Fed balance sheet and Treasury cash balance"),
            NJInvestmentMacroSignal(id: "us-rates-curve", market: .us, title: "Rates And Curve", status: "Mixed", note: "Track 2Y, 10Y, 30Y, real yields, curve shape, and rate-cut odds. Equity duration risk changes fast when real yields rise.", nextCatalyst: "Treasury auctions, CPI/PCE, Fed speakers"),
            NJInvestmentMacroSignal(id: "us-credit", market: .us, title: "Credit Stress", status: "Calm", note: "High-yield spreads, IG spreads, loan stress, and default rates are the pullback smoke alarm before equities fully react.", nextCatalyst: "HY spread, senior loan officer survey, default updates"),
            NJInvestmentMacroSignal(id: "us-consumer-labor", market: .us, title: "Consumer And Labor", status: "Watch", note: "Retail control group, income, savings, delinquencies, payrolls, claims, wages, and hours worked show whether demand is cracking.", nextCatalyst: "Claims, payrolls, retail sales, consumer sentiment"),
            NJInvestmentMacroSignal(id: "us-earnings-breadth", market: .us, title: "Earnings And Breadth", status: "Supportive", note: "Mag 7 earnings, S&P EPS revisions, equal-weight versus cap-weight, VIX, MOVE, and 50/200DMA breadth connect macro to market tape.", nextCatalyst: "Nvidia earnings and S&P revision breadth"),
            NJInvestmentMacroSignal(id: "china-hk-liquidity", market: .chinaHK, title: "China Credit Impulse", status: "Watch", note: "Track credit impulse, policy support, property stress, northbound/southbound flow, and RMB/HKD liquidity.", nextCatalyst: "China activity data, PBOC liquidity, policy meetings"),
            NJInvestmentMacroSignal(id: "china-hk-fx-property", market: .chinaHK, title: "FX And Property Stress", status: "Mixed", note: "USDCNH, USDHKD peg pressure, HIBOR, developer financing, and HK property stress determine whether HK beta can hold rallies.", nextCatalyst: "HIBOR, aggregate balance, property-credit headlines"),
            NJInvestmentMacroSignal(id: "japan-boj-jgb", market: .japan, title: "BOJ And JGB", status: "Stress", note: "BOJ path, JGB 10Y/30Y, wage and inflation data, and JPY carry stress are the cross-market trigger for June risk.", nextCatalyst: "BOJ decision, Tokyo CPI, JGB auction demand"),
            NJInvestmentMacroSignal(id: "japan-fx-carry", market: .japan, title: "JPY Carry Stress", status: "Watch", note: "USDJPY, yen funding conditions, and exporter equity reaction show whether Japan is becoming a global risk-off catalyst.", nextCatalyst: "USDJPY breaks, BOJ guidance, global beta reaction"),
            NJInvestmentMacroSignal(id: "europe-ecb-bund", market: .europe, title: "ECB, Bund And Gilt", status: "Watch", note: "ECB path, Germany Bund yields, UK gilt yields, peripheral spreads, and bank credit decide whether Europe adds to or dampens global duration stress.", nextCatalyst: "ECB decision, Euro Area CPI, Bund/Gilt auction demand"),
            NJInvestmentMacroSignal(id: "europe-growth-fx", market: .europe, title: "Europe Growth And FX", status: "Mixed", note: "Euro Area PMIs, retail sales, unemployment, EUR/USD, and bank lending show whether Europe is a risk-on support or global slowdown signal.", nextCatalyst: "PMI, HICP, retail sales, bank lending survey"),
            NJInvestmentMacroSignal(id: "commodity-crypto-liquidity", market: .crypto, title: "Crypto Liquidity", status: "Watch", note: "BTC, ETH, stablecoin supply, ETF flows, regulation, and exchange risk show whether crypto confirms or diverges from risk appetite.", nextCatalyst: "ETF flows, stablecoin supply, regulatory deadlines"),
            NJInvestmentMacroSignal(id: "commodity-crypto-inflation", market: .crypto, title: "Oil And Metals", status: "Stress", note: "Brent, WTI, gold, and silver track inflation shock, debasement demand, and geopolitical stress.", nextCatalyst: "EIA inventories, OPEC, war/oil headlines, real yields")
        ]
    }

    private var marketChecklists: [NJInvestmentMarketChecklist] {
        [
            NJInvestmentMarketChecklist(id: "us", market: .us, title: "US Market", items: ["Liquidity: Fed balance sheet, QT, TGA, reverse repo, reserves", "Inflation and consumer: CPI, PCE, retail sales, sentiment, savings, delinquencies", "Rates and credit: 2Y/10Y/30Y, real yield, auctions, HY/IG spreads, defaults", "Labor and earnings: payrolls, claims, wages, hours, Mag 7 earnings, breadth, VIX/MOVE"]),
            NJInvestmentMarketChecklist(id: "china-hk", market: .chinaHK, title: "HK / China", items: ["Credit impulse, PBOC liquidity, property stress, developer financing", "CPI, PPI, retail sales, employment, industrial production", "USDCNH, USDHKD, HIBOR, HK aggregate balance, peg pressure", "Northbound/southbound flow, policy meetings, tariffs, export controls"]),
            NJInvestmentMarketChecklist(id: "japan", market: .japan, title: "Japan", items: ["BOJ meetings, inflation, wages, JGB 10Y/30Y, auction demand", "JPY FX and carry-trade stress", "Consumer data, employment, equity leadership, exporter sensitivity", "Debt sustainability, BOJ balance sheet, global duration spillover"]),
            NJInvestmentMarketChecklist(id: "europe", market: .europe, title: "Europe", items: ["ECB meetings, HICP, PMIs, retail sales, unemployment, wage pressure", "Germany 10Y Bund, UK 10Y gilt, peripheral spreads, auction demand, bank lending survey", "EUR/USD, energy sensitivity, European banks and cyclicals", "Fiscal stress, France/Germany/UK politics, credit impulse, global duration spillover"]),
            NJInvestmentMarketChecklist(id: "commodity-crypto", market: .crypto, title: "Commodity / Crypto", items: ["BTC and ETH spot trend, ETF flows, stablecoin supply", "Brent and WTI as inflation / supply-shock signal", "Gold and silver as debasement and stress hedges", "OPEC, EIA inventories, regulation, exchange risk, protocol/security incidents"])
        ]
    }
}
