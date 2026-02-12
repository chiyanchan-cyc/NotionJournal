import SwiftUI

private enum NJGoalStatusTab: String, CaseIterable, Identifiable {
    case seedling = "Seedling"
    case inProgress = "In Progress"
    case archive = "Archive"

    var id: String { rawValue }
}

struct NJGoalSidebarView: View {
    @EnvironmentObject var store: AppStore

    @State private var goals: [NJGoalSummary] = []
    @State private var statusTab: NJGoalStatusTab = .seedling
    @State private var searchText: String = ""
    @State private var mainDomain: String = "ME"
    @State private var selectedSecondTierDomains: Set<String> = ["ALL"]
    @State private var showGoalCreate = false

    private let staleDays: Int = 14
    private let railWidth: CGFloat = 72
    private let mainDomainTabs: [String] = ["ME", "ZZ", "MM", "DEV"]

    var body: some View {
        VStack(spacing: 0) {
            topTabs()
            Divider()
            HStack(spacing: 0) {
                domainRail()
                Divider()
                VStack(spacing: 0) {
                    secondTierFilterBar()
                    Divider()
                    goalList()
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .njGoalUpdated)) { _ in
            reload()
        }
        .sheet(isPresented: $showGoalCreate, onDismiss: { reload() }) {
            NavigationStack {
                NJGoalCreateSheet(repo: store.notes, originBlockID: nil)
            }
        }
    }

    private func topTabs() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        goalTabButton("Seedling", isOn: statusTab == .seedling) {
                            statusTab = .seedling
                            store.selectedGoalID = nil
                        }
                        goalTabButton("In Progress", isOn: statusTab == .inProgress) {
                            statusTab = .inProgress
                            store.selectedGoalID = nil
                        }
                        goalTabButton("Archive", isOn: statusTab == .archive) {
                            statusTab = .archive
                            store.selectedGoalID = nil
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.vertical, 10)
                }

                Button {
                    showGoalCreate = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(UIColor.secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
        }
        .background(Color(UIColor.systemBackground))
    }

    private func goalTabButton(_ text: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isOn ? Color.accentColor.opacity(0.22) : Color(UIColor.secondarySystemBackground))
                Text(text)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
                    .frame(width: 96, alignment: .center)
                    .foregroundStyle(.primary)
            }
            .frame(width: 110, height: 44)
        }
        .buttonStyle(.plain)
    }

    private func domainRail() -> some View {
        GeometryReader { g in
            let H = g.size.height
            let tabs = mainDomainTabs
            let tabCount = tabs.count
            let spacing: CGFloat = 12
            let tabMin: CGFloat = 72
            let tabMax: CGFloat = 176
            let topBottomPad: CGFloat = 24
            let usableForTabs = max(0, H - topBottomPad - (tabCount > 0 ? spacing * CGFloat(max(0, tabCount - 1)) : 0))
            let rawTab = tabCount > 0 ? usableForTabs / CGFloat(tabCount) : tabMax
            let tabHeight = min(tabMax, max(tabMin, rawTab))
            let small = tabHeight < 100
            let tabFontSize: CGFloat = small ? 10 : 12
            let tabLineLimit = 2
            let colorHex = Color.accentColor.toHexString()

            VStack(spacing: spacing) {
                ForEach(tabs, id: \.self) { t in
                    Button {
                        mainDomain = t
                        selectedSecondTierDomains = ["ALL"]
                        store.selectedGoalID = nil
                    } label: {
                        RotatedWrapLabel(
                            text: t,
                            railWidth: railWidth,
                            buttonHeight: tabHeight,
                            fontSize: tabFontSize,
                            lineLimit: tabLineLimit,
                            isOn: mainDomain == t,
                            colorHex: colorHex
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: railWidth, height: tabHeight)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .frame(width: railWidth)
            .background(Color(UIColor.secondarySystemBackground))
        }
        .frame(width: railWidth)
    }

    private func secondTierFilterBar() -> some View {
        let filters = secondTierDomainFilters()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Button {
                        toggleSecondTierFilter(filter)
                        store.selectedGoalID = nil
                    } label: {
                        Text(filter)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isSecondTierFilterOn(filter) ? Color.accentColor.opacity(0.22) : Color(UIColor.secondarySystemBackground))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.systemBackground))
    }

    private func goalList() -> some View {
        List(selection: $store.selectedGoalID) {
            let filtered = filteredGoals()
            if filtered.isEmpty {
                Text("No goals")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filtered) { item in
                    Button {
                        store.selectedGoalID = item.goalID
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name.isEmpty ? "Untitled" : item.name)
                                .font(.body)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            if !item.goalTag.isEmpty {
                                Text(item.goalTag)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text(lastUpdatedString(item.updatedAtMs))
                                .font(.caption2)
                                .foregroundStyle(isStale(item.updatedAtMs) ? .red : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .tag(item.goalID)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func filteredGoals() -> [NJGoalSummary] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return goals.filter { item in
            if statusFor(item.status, goalTag: item.goalTag) != statusTab { return false }
            let domains = parseDomainTags(item.domainTagsJSON)
            if !passesDomainFilter(domains) { return false }
            if trimmedSearch.isEmpty { return true }
            if item.name.lowercased().contains(trimmedSearch) { return true }
            if item.goalTag.lowercased().contains(trimmedSearch) { return true }
            return false
        }
    }

    private func secondTierDomainFilters() -> [String] {
        var set = Set<String>()
        for g in goals {
            let domains = parseDomainTags(g.domainTagsJSON)
            for d in domains {
                if let key = secondTierKey(of: d), topLevelDomain(of: key) == mainDomain {
                    set.insert(key)
                }
            }
        }
        let sorted = Array(set).sorted()
        return ["ALL"] + sorted
    }

    private func secondTierKey(of domain: String) -> String? {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return nil }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: true)
        if parts.count < 2 { return nil }
        return "\(parts[0]).\(parts[1])"
    }

    private func topLevelDomain(of domain: String) -> String {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first.map { String($0).uppercased() } ?? ""
    }

    private func passesDomainFilter(_ domains: [String]) -> Bool {
        let mainMatches = domains
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { topLevelDomain(of: $0) == mainDomain }
        if mainMatches.isEmpty { return false }
        if selectedSecondTierDomains.contains("ALL") { return true }

        let keys = Set(mainMatches.compactMap { secondTierKey(of: $0) })
        if keys.isEmpty { return false }
        return !keys.isDisjoint(with: selectedSecondTierDomains)
    }

    private func isSecondTierFilterOn(_ filter: String) -> Bool {
        let key = filter.uppercased() == "ALL" ? "ALL" : filter.lowercased()
        return selectedSecondTierDomains.contains(key)
    }

    private func toggleSecondTierFilter(_ filter: String) {
        let isAll = filter.uppercased() == "ALL"
        let key = isAll ? "ALL" : filter.lowercased()

        if isAll {
            selectedSecondTierDomains = ["ALL"]
            return
        }

        selectedSecondTierDomains.remove("ALL")
        if selectedSecondTierDomains.contains(key) {
            selectedSecondTierDomains.remove(key)
        } else {
            selectedSecondTierDomains.insert(key)
        }
        if selectedSecondTierDomains.isEmpty {
            selectedSecondTierDomains = ["ALL"]
        }
    }

    private func parseDomainTags(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return arr
    }

    private func statusFor(_ status: String, goalTag: String) -> NJGoalStatusTab {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["archive", "archived", "done", "closed"].contains(s) { return .archive }
        let trimmedTag = goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty { return .inProgress }
        if ["in_progress", "in progress", "in-progress", "progress", "active", "working"].contains(s) { return .inProgress }
        if s.isEmpty { return .seedling }
        if s == "open" { return .seedling }
        return .seedling
    }

    private func isStale(_ updatedAtMs: Int64) -> Bool {
        if updatedAtMs <= 0 { return true }
        let now = Date().timeIntervalSince1970 * 1000.0
        let ageMs = now - Double(updatedAtMs)
        return ageMs > Double(staleDays) * 24 * 60 * 60 * 1000
    }

    private func lastUpdatedString(_ ms: Int64) -> String {
        if ms <= 0 { return "-" }
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func reload() {
        goals = store.notes.listGoalSummaries()
        let available = Set(goals.flatMap { parseDomainTags($0.domainTagsJSON).map { topLevelDomain(of: $0) } }.filter { !$0.isEmpty })
        if !available.contains(mainDomain) {
            if let firstAvailable = mainDomainTabs.first(where: { available.contains($0) }) {
                mainDomain = firstAvailable
            } else {
                mainDomain = mainDomainTabs.first ?? "ME"
            }
            selectedSecondTierDomains = ["ALL"]
        } else {
            let valid = Set(secondTierDomainFilters().dropFirst().map { $0.lowercased() })
            if !selectedSecondTierDomains.contains("ALL") {
                let kept = selectedSecondTierDomains.intersection(valid)
                selectedSecondTierDomains = kept.isEmpty ? ["ALL"] : kept
            }
        }
    }
}
