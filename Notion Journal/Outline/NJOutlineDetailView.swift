import SwiftUI
import PhotosUI
#if os(iOS)
import UIKit
import WebKit
import PencilKit
import Vision
#endif

struct NJOutlineDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var outline: NJOutlineStore

    let outlineID: String

    @State private var showDeleteBlocked = false
    @State private var isReorderMode = false
    @State private var showComments = false
    @State private var experimentalInkMode = false
    @State private var experimentalGanttMode = false
    @State private var showHandwritingSheet = false
    @State private var inkNodePositions: [String: CGPoint] = [:]
    @State private var showInkRenameSheet = false
    @State private var inkRenameNodeID: String? = nil
    @State private var inkRenameDraft: String = ""
    @State private var inkRenameStartEnabled = false
    @State private var inkRenameEndEnabled = false
    @State private var inkRenameStartDate = Date()
    @State private var inkRenameEndDate = Date()
    @State private var showRenameKeyboard = false
    @State private var renameFieldFocused = false
    @FocusState private var inkRenameFocused: Bool
    @State private var showInkNodeMenu = false
    @State private var inkMenuNodeID: String? = nil
    @State private var showInkNodePopover = false
    @State private var inkMenuAnchorPoint: CGPoint = CGPoint(x: 120, y: 120)
    @State private var showMindmapScheduleSheet = false
    @State private var mindmapScheduleNodeID: String? = nil
    @State private var mindmapStartEnabled = false
    @State private var mindmapEndEnabled = false
    @State private var mindmapStartDate = Date()
    @State private var mindmapEndDate = Date()
    @State private var inkCanvasScale: CGFloat = 1.0
    @State private var inkCanvasBaseScale: CGFloat = 1.0
    @State private var showPhoneDetailSheet = false
    @State private var phoneDetailNodeID: String? = nil
    @State private var temporaryFocusNodeID: String? = nil
    @State private var pinnedFocusNodeID: String? = nil
    @State private var outlineDateFilter: MindmapDateFilter = .thisMonth
    @State private var mindmapDateFilter: MindmapDateFilter = .thisMonth
    @State private var ganttTimeScope: GanttTimeScope = .monthly
    @State private var ganttPlanningMode = false
    @State private var showGanttTaskSheet = false
    @State private var ganttTaskNodeID: String? = nil
    @State private var ganttTaskProgressPct: Double = 0
    @FocusState private var focusedNodeID: String?

    private enum GanttTimeScope: String, CaseIterable {
        case yearly
        case quarterly
        case monthly

        var label: String {
            switch self {
            case .yearly: return "Y"
            case .quarterly: return "Q"
            case .monthly: return "M"
            }
        }

        var title: String {
            switch self {
            case .yearly: return "Year"
            case .quarterly: return "Quarter"
            case .monthly: return "Month"
            }
        }

        var frappeViewMode: String {
            switch self {
            case .yearly: return "Month"
            case .quarterly: return "Week"
            case .monthly: return "Day"
            }
        }
    }

    private enum MindmapDateFilter: String, CaseIterable {
        case all
        case thisYear
        case thisQuarter
        case thisMonth
        case thisDay

        var label: String {
            switch self {
            case .all: return "ALL"
            case .thisYear: return "Y"
            case .thisQuarter: return "Q"
            case .thisMonth: return "M"
            case .thisDay: return "D"
            }
        }

        static var visibleFilterCases: [MindmapDateFilter] {
            [.thisYear, .thisQuarter, .thisMonth, .thisDay]
        }
    }

    private struct GanttVisibleNode {
        let node: NJOutlineNodeRecord
        let depth: Int
        let pathLabel: String
        let hasChildren: Bool
        let displayStartMs: Int64
        let displayEndMs: Int64
        let hasOwnSchedule: Bool
    }

    private var rows: [NJOutlineNodeRow] {
        outline.nodeRows(outlineID: outlineID)
    }

    private var outlineDisplayRows: [NJOutlineNodeRow] {
        if isReorderMode { return rows }
        return filteredRows(for: outlineDateFilter)
    }

    private var effectiveSelectedNodeID: String? {
        if let focused = focusedNodeID,
           rows.contains(where: { $0.node.nodeID == focused }) {
            return focused
        }
        if let selected = store.selectedOutlineNodeID,
           rows.contains(where: { $0.node.nodeID == selected }) {
            return selected
        }
        return rows.first?.node.nodeID
    }

    private var outlineTitle: String {
        let t = outline.outlines.first(where: { $0.outlineID == outlineID })?.title ?? ""
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Outline" : trimmed
    }

    private var activeFocusNodeID: String? {
        pinnedFocusNodeID ?? temporaryFocusNodeID
    }

    private var isIPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private var isIPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar()
            Divider()
            if experimentalGanttMode && isIPad {
                experimentalGanttWorkspace()
            } else if experimentalInkMode && isIPad {
                experimentalInkCanvas()
            } else {
                if outlineDisplayRows.isEmpty {
                    ContentUnavailableView("No nodes", systemImage: "list.bullet")
                } else {
                    List {
                        if isReorderMode {
                            ForEach(Array(outlineDisplayRows.enumerated()), id: \.element.id) { idx, row in
                                nodeRow(row)
                                    .font(.system(size: 12))
                                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                                    .listRowBackground(rowBackground(idx: idx))
                            }
                            .onMove(perform: moveRows)
                        } else {
                            ForEach(Array(outlineDisplayRows.enumerated()), id: \.element.id) { idx, row in
                                nodeRow(row)
                                    .font(.system(size: 12))
                                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                                    .listRowBackground(rowBackground(idx: idx))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .id("outline-list-\(outlineDateFilter.rawValue)")
                    .environment(\.defaultMinListRowHeight, showComments ? 44 : 28)
                    .environment(\.editMode, .constant(isReorderMode ? .active : .inactive))
                }
            }
        }
        .onAppear {
            outline.loadNodes(outlineID: outlineID)
            resetInkLayoutPersisted()
            pruneInkPositions()
            if experimentalInkMode && experimentalGanttMode {
                experimentalGanttMode = false
            }
        }
        .onChange(of: outline.nodes) { _, _ in
            guard store.selectedOutlineNodeID == nil else { return }
            if let first = rows.first?.node.nodeID {
                store.selectedOutlineNodeID = first
            }
            pruneInkPositions()
            let validIDs = Set(rows.map { $0.node.nodeID })
            if let pinnedFocusNodeID, !validIDs.contains(pinnedFocusNodeID) {
                self.pinnedFocusNodeID = nil
            }
            if let temporaryFocusNodeID, !validIDs.contains(temporaryFocusNodeID) {
                self.temporaryFocusNodeID = nil
            }
        }
        .onChange(of: focusedNodeID) { _, newID in
            guard let newID else { return }
            store.selectedOutlineNodeID = newID
        }
        .alert("Cannot Delete Node", isPresented: $showDeleteBlocked) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This node has dependencies. Remove child nodes/references first.")
        }
        .sheet(isPresented: $showInkRenameSheet) {
            NavigationStack {
                Form {
                    Section("Node Title") {
                        NJKeyboardControlledTextField(
                            text: $inkRenameDraft,
                            placeholder: "Untitled",
                            keyboardVisible: $showRenameKeyboard,
                            isFirstResponder: $renameFieldFocused
                        )
                        .frame(minHeight: 28)
                    }
                    Section("Timeline") {
                        Toggle("Start", isOn: $inkRenameStartEnabled)
                        if inkRenameStartEnabled {
                            DatePicker("Start Date", selection: $inkRenameStartDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }
                        Toggle("Deadline (End)", isOn: $inkRenameEndEnabled)
                        if inkRenameEndEnabled {
                            DatePicker("End Date", selection: $inkRenameEndDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }
                    }
                }
                .navigationTitle("Edit Node")
                .onAppear {
                    showRenameKeyboard = false
                    renameFieldFocused = true
                }
                .onChange(of: inkRenameStartEnabled) { _, _ in normalizeInkRenameDateRange() }
                .onChange(of: inkRenameStartDate) { _, _ in normalizeInkRenameDateRange() }
                .onChange(of: inkRenameEndEnabled) { _, _ in normalizeInkRenameDateRange() }
                .onChange(of: inkRenameEndDate) { _, _ in normalizeInkRenameDateRange() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showInkRenameSheet = false }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            if !inkRenameDraft.isEmpty {
                                inkRenameDraft.removeLast()
                            }
                            renameFieldFocused = true
                        } label: {
                            Label("Delete", systemImage: "delete.left")
                        }
                        .disabled(inkRenameDraft.isEmpty)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            showRenameKeyboard.toggle()
                            renameFieldFocused = true
                        } label: {
                            Image(systemName: showRenameKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            normalizeInkRenameDateRange()
                            if let id = inkRenameNodeID {
                                outline.updateNodeTitle(nodeID: id, title: inkRenameDraft)
                                var filter = outline.nodeFilter(nodeID: id)
                                if inkRenameStartEnabled {
                                    filter["start_ms"] = dayStartMs(inkRenameStartDate)
                                } else {
                                    filter.removeValue(forKey: "start_ms")
                                }
                                if inkRenameEndEnabled {
                                    filter["end_ms"] = dayEndMs(inkRenameEndDate)
                                } else {
                                    filter.removeValue(forKey: "end_ms")
                                }
                                outline.setNodeFilter(nodeID: id, filter: filter)
                                requestImmediateCloudPush()
                            }
                            showInkRenameSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPhoneDetailSheet) {
            if let nodeID = phoneDetailNodeID {
                NavigationStack {
                    NJOutlineNodeDetailWindowView(outline: outline, nodeID: nodeID)
                        .environmentObject(store)
                }
            }
        }
        .sheet(isPresented: $showHandwritingSheet) {
            NJOutlineHandwritingSheet { action, recognized in
                let text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                switch action {
                case .replaceSelected:
                    if let selected = effectiveSelectedNodeID {
                        outline.updateNodeTitle(nodeID: selected, title: text)
                        store.selectedOutlineNodeID = selected
                        focusedNodeID = selected
                    } else {
                        let created = outline.createRootNode(outlineID: outlineID)
                        outline.updateNodeTitle(nodeID: created.nodeID, title: text)
                        store.selectedOutlineNodeID = created.nodeID
                        focusedNodeID = created.nodeID
                    }
                case .appendSelected:
                    if let selected = effectiveSelectedNodeID,
                       let current = outline.node(selected) {
                        let base = current.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let merged = base.isEmpty ? text : "\(base) \(text)"
                        outline.updateNodeTitle(nodeID: selected, title: merged)
                        store.selectedOutlineNodeID = selected
                        focusedNodeID = selected
                    } else {
                        let created = outline.createRootNode(outlineID: outlineID)
                        outline.updateNodeTitle(nodeID: created.nodeID, title: text)
                        store.selectedOutlineNodeID = created.nodeID
                        focusedNodeID = created.nodeID
                    }
                case .newChild:
                    if let selected = effectiveSelectedNodeID,
                       let created = outline.createChildNode(nodeID: selected) {
                        outline.updateNodeTitle(nodeID: created.nodeID, title: text)
                        store.selectedOutlineNodeID = created.nodeID
                        focusedNodeID = created.nodeID
                    } else {
                        let created = outline.createRootNode(outlineID: outlineID)
                        outline.updateNodeTitle(nodeID: created.nodeID, title: text)
                        store.selectedOutlineNodeID = created.nodeID
                        focusedNodeID = created.nodeID
                    }
                }
            }
        }
        .sheet(isPresented: $showMindmapScheduleSheet) {
            NavigationStack {
                Form {
                    Section("Timeline") {
                        Toggle("Start", isOn: $mindmapStartEnabled)
                        if mindmapStartEnabled {
                            DatePicker("Start Date", selection: $mindmapStartDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }

                        Toggle("Deadline (End)", isOn: $mindmapEndEnabled)
                        if mindmapEndEnabled {
                            DatePicker("End Date", selection: $mindmapEndDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }
                    }
                }
                .font(.system(size: 12))
                .navigationTitle(scheduleSheetTitle())
                .onChange(of: mindmapStartEnabled) { _, _ in normalizeMindmapScheduleDateRange() }
                .onChange(of: mindmapStartDate) { _, _ in normalizeMindmapScheduleDateRange() }
                .onChange(of: mindmapEndEnabled) { _, _ in normalizeMindmapScheduleDateRange() }
                .onChange(of: mindmapEndDate) { _, _ in normalizeMindmapScheduleDateRange() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showMindmapScheduleSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveMindmapSchedule()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showGanttTaskSheet) {
            NavigationStack {
                Form {
                    Section("Progress") {
                        HStack {
                            Slider(value: $ganttTaskProgressPct, in: 0...100, step: 1)
                            Text("\(Int(ganttTaskProgressPct))%")
                                .frame(width: 46, alignment: .trailing)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .font(.system(size: 12))
                .navigationTitle(ganttTaskSheetTitle())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showGanttTaskSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveGanttTaskProgress()
                        }
                    }
                }
            }
            .presentationDetents([.fraction(0.28), .medium])
        }
        .confirmationDialog(
            "Node Actions",
            isPresented: $showInkNodeMenu,
            titleVisibility: .visible
        ) {
            if let nodeID = inkMenuNodeID {
                Button("Edit") {
                    performInkMenuEdit(nodeID)
                }
                Button("Add Child") {
                    performInkMenuAddChild(nodeID)
                }
                Button("Add Sibling") {
                    performInkMenuAddSibling(nodeID)
                }
                Button("Delete", role: .destructive) {
                    performInkMenuDelete(nodeID)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    @ViewBuilder
    private func inkNodePopoverContent() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let nodeID = inkMenuNodeID { performInkMenuEdit(nodeID) }
                showInkNodePopover = false
            } label: {
                popoverMenuRow("pencil", "Edit")
            }
            Button {
                if let nodeID = inkMenuNodeID { performInkMenuAddChild(nodeID) }
                showInkNodePopover = false
            } label: {
                popoverMenuRow("arrowshape.turn.up.left", "Add Child")
            }
            Button {
                if let nodeID = inkMenuNodeID { performInkMenuAddSibling(nodeID) }
                showInkNodePopover = false
            } label: {
                popoverMenuRow("plus.square.on.square", "Add Sibling")
            }
            Divider()
            Button(role: .destructive) {
                if let nodeID = inkMenuNodeID { performInkMenuDelete(nodeID) }
                showInkNodePopover = false
            } label: {
                popoverMenuRow("trash", "Delete")
            }
        }
        .font(.system(size: 16))
        .buttonStyle(.plain)
        .padding(12)
        .frame(minWidth: 240, alignment: .leading)
    }

    private func popoverMenuRow(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
            Text(title)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func performInkMenuEdit(_ nodeID: String) {
        if let node = outline.node(nodeID) {
            startEditingInkNode(nodeID: nodeID, title: node.title)
        }
    }

    private func performInkMenuAddChild(_ nodeID: String) {
        if let n = outline.createChildNode(nodeID: nodeID) {
            store.selectedOutlineNodeID = n.nodeID
            if experimentalInkMode {
                startEditingInkNode(nodeID: n.nodeID, title: n.title)
            }
        }
    }

    private func performInkMenuAddSibling(_ nodeID: String) {
        if let n = outline.createSiblingNode(nodeID: nodeID) {
            applyGanttSiblingScheduleIfNeeded(fromSelectedNodeID: nodeID, toCreatedNodeID: n.nodeID)
            store.selectedOutlineNodeID = n.nodeID
            if experimentalInkMode {
                startEditingInkNode(nodeID: n.nodeID, title: n.title)
            }
        }
    }

    private func performInkMenuDelete(_ nodeID: String) {
        if outline.canDeleteNode(nodeID: nodeID) {
            outline.deleteNode(nodeID: nodeID)
            if store.selectedOutlineNodeID == nodeID {
                store.selectedOutlineNodeID = rows.first?.node.nodeID
            }
        } else {
            showDeleteBlocked = true
        }
    }

    private func presentInkNodeMenu(nodeID: String?, at point: CGPoint?) {
        guard let nodeID else {
            showInkNodeMenu = false
            showInkNodePopover = false
            return
        }
        inkMenuNodeID = nodeID
        if experimentalInkMode, isIPad {
            if let point {
                inkMenuAnchorPoint = point
            }
            let wasShowingPopover = showInkNodePopover
            showInkNodeMenu = false
            if wasShowingPopover {
                showInkNodePopover = false
                DispatchQueue.main.async {
                    // SwiftUI popover won't reliably move while already presented;
                    // re-present so the new anchor point is applied.
                    showInkNodePopover = true
                }
            } else {
                showInkNodePopover = true
            }
        } else {
            showInkNodePopover = false
            showInkNodeMenu = true
        }
    }

    private func topBar() -> some View {
        VStack(spacing: 6) {
            if experimentalInkMode || experimentalGanttMode {
                HStack {
                    Spacer()
                    Text(outlineTitle)
                        .font(.custom("BradleyHandITCTT-Bold", size: 24))
                        .lineLimit(1)
                    Spacer()
                }
                if experimentalInkMode,
                   let selectedID = effectiveSelectedNodeID,
                   let selectedNode = outline.node(selectedID) {
                    let t = selectedNode.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text("Target: \(t.isEmpty ? "Untitled" : t)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                if experimentalInkMode,
                   let activeFocusNodeID, let focusNode = outline.node(activeFocusNodeID) {
                    Text("Focus: \(focusNode.title.isEmpty ? "Untitled" : focusNode.title)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if experimentalInkMode {
                    HStack(spacing: 6) {
                        Text("Filtered")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        ForEach(MindmapDateFilter.visibleFilterCases, id: \.rawValue) { filter in
                            Button {
                                mindmapDateFilter = filter
                            } label: {
                                Text(filter.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(mindmapDateFilter == filter ? .white : .primary)
                                    .frame(minWidth: 28, minHeight: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(mindmapDateFilter == filter ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 2)
                }
                if experimentalGanttMode {
                    HStack(spacing: 6) {
                        Button {
                            ganttPlanningMode = false
                        } label: {
                            Text("Timeline")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ganttPlanningMode ? .primary : .white)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(ganttPlanningMode ? Color(UIColor.secondarySystemBackground) : Color.accentColor)
                                )
                        }
                        .buttonStyle(.plain)
                        Button {
                            ganttPlanningMode = true
                        } label: {
                            Text("Plan")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ganttPlanningMode ? .white : .primary)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(ganttPlanningMode ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 2)
                    HStack(spacing: 6) {
                        Text("Filtered")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Menu {
                            ForEach(GanttTimeScope.allCases, id: \.rawValue) { scope in
                                Button {
                                    ganttTimeScope = scope
                                } label: {
                                    if ganttTimeScope == scope {
                                        Label(scope.title, systemImage: "checkmark")
                                    } else {
                                        Text(scope.title)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(ganttTimeScope.title)
                                    .font(.system(size: 11, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(UIColor.secondarySystemBackground))
                            )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 2)
                }
            } else {
                HStack {
                    Text(outlineTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
                HStack(spacing: 6) {
                    Text("Filtered")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    ForEach(MindmapDateFilter.visibleFilterCases, id: \.rawValue) { filter in
                        Button {
                            outlineDateFilter = filter
                        } label: {
                            Text(filter.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(outlineDateFilter == filter ? .white : .primary)
                                .frame(minWidth: 28, minHeight: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(outlineDateFilter == filter ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 8) {
                iconButton("plus") {
                    if let selected = effectiveSelectedNodeID,
                       let n = outline.createSiblingNode(nodeID: selected) {
                        applyGanttSiblingScheduleIfNeeded(fromSelectedNodeID: selected, toCreatedNodeID: n.nodeID)
                        store.selectedOutlineNodeID = n.nodeID
                        if experimentalInkMode {
                            startEditingInkNode(nodeID: n.nodeID, title: n.title)
                        }
                    } else {
                        let n = outline.createRootNode(outlineID: outlineID)
                        store.selectedOutlineNodeID = n.nodeID
                        if experimentalInkMode {
                            startEditingInkNode(nodeID: n.nodeID, title: n.title)
                        }
                    }
                }

            if let nodeID = effectiveSelectedNodeID {
                iconButton("plus.square.on.square") {
                    if let n = outline.createSiblingNode(nodeID: nodeID) {
                        applyGanttSiblingScheduleIfNeeded(fromSelectedNodeID: nodeID, toCreatedNodeID: n.nodeID)
                        store.selectedOutlineNodeID = n.nodeID
                        if experimentalInkMode {
                            startEditingInkNode(nodeID: n.nodeID, title: n.title)
                        }
                    }
                    }
                    iconButton("arrowshape.turn.up.left") {
                        if let n = outline.createChildNode(nodeID: nodeID) {
                            store.selectedOutlineNodeID = n.nodeID
                            if experimentalInkMode {
                                startEditingInkNode(nodeID: n.nodeID, title: n.title)
                            }
                        }
                    }
                    iconButton("arrow.up.left") {
                        outline.promote(nodeID: nodeID)
                    }
                    iconButton("arrow.down.right") {
                        outline.demote(nodeID: nodeID)
                    }
                    iconButton("trash") {
                        if outline.canDeleteNode(nodeID: nodeID) {
                            outline.deleteNode(nodeID: nodeID)
                            if store.selectedOutlineNodeID == nodeID {
                                store.selectedOutlineNodeID = nil
                            }
                        } else {
                            showDeleteBlocked = true
                        }
                    }
                    if experimentalInkMode {
                        iconButton("pencil") {
                            if let selected = effectiveSelectedNodeID,
                               let node = outline.node(selected) {
                                startEditingInkNode(nodeID: selected, title: node.title)
                            }
                        }
                        iconButton("scope") {
                            temporaryFocusNodeID = nodeID
                        }
                        iconButton((pinnedFocusNodeID == nodeID) ? "pin.fill" : "pin") {
                            if pinnedFocusNodeID == nodeID {
                                pinnedFocusNodeID = nil
                            } else {
                                pinnedFocusNodeID = nodeID
                            }
                        }
                    }
                }

                iconButton(isReorderMode ? "checkmark" : "line.3.horizontal") {
                    isReorderMode.toggle()
                }
                iconButton(showComments ? "text.bubble.fill" : "text.bubble") {
                    showComments.toggle()
                }
                if isIPad {
                    iconButton(experimentalInkMode ? "text.alignleft" : "map") {
                        experimentalInkMode.toggle()
                        if experimentalInkMode { experimentalGanttMode = false }
                    }
                    iconButton(experimentalGanttMode ? "text.alignleft" : "calendar") {
                        experimentalGanttMode.toggle()
                        if experimentalGanttMode { experimentalInkMode = false }
                    }
                    iconButton("uiwindow.split.2x1") {
                        openWindow(id: "outline-detached", value: outlineID)
                    }
                    if experimentalInkMode {
                        iconButton("pencil.tip.crop.circle.badge.plus") {
                            showHandwritingSheet = true
                        }
                        if activeFocusNodeID != nil {
                            iconButton("xmark.circle") {
                                temporaryFocusNodeID = nil
                                pinnedFocusNodeID = nil
                            }
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(UIColor.systemBackground))
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(idx: Int) -> Color {
        if colorScheme == .dark {
            return idx.isMultiple(of: 2) ? Color(UIColor.secondarySystemBackground) : Color(UIColor.tertiarySystemBackground)
        }
        return idx.isMultiple(of: 2) ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground)
    }

    private func nodeRow(_ row: NJOutlineNodeRow) -> some View {
        let n = row.node
        let progress = outlineProgressRatio(nodeID: n.nodeID)
        return HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(row.depth) * 14)

            Button {
                if n.isChecklist {
                    outline.toggleChecked(nodeID: n.nodeID)
                } else {
                    outline.toggleChecklist(nodeID: n.nodeID)
                }
            } label: {
                Image(systemName: n.isChecklist ? (n.isChecked ? "checkmark.circle.fill" : "circle") : "circle")
                    .foregroundColor(n.isChecked ? .accentColor : .secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            Group {
                if hasChildren(n.nodeID) {
                    Button {
                        outline.toggleCollapsed(nodeID: n.nodeID)
                    } label: {
                        Image(systemName: n.isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                TextField(
                    "Untitled",
                    text: Binding(
                        get: { n.title },
                        set: {
                            store.selectedOutlineNodeID = n.nodeID
                            outline.updateNodeTitle(nodeID: n.nodeID, title: $0)
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focusedNodeID, equals: n.nodeID)

                if showComments {
                    let c = n.comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !c.isEmpty {
                        Text(c)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 4)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ProgressView(value: progress, total: 1)
                    .progressViewStyle(.linear)
                    .frame(width: 64)
                Text("\(Int((progress * 100.0).rounded()))%")
                    .frame(width: 36, alignment: .trailing)
            }
            .font(.system(size: 10))
            .foregroundColor(progress >= 1.0 ? .green : .secondary)
            .padding(.trailing, 6)

            let schedule = outlineRowScheduleColumns(nodeID: n.nodeID)
            HStack(spacing: 6) {
                Text(schedule.start)
                    .frame(width: 62, alignment: .trailing)
                Text(schedule.end)
                    .frame(width: 62, alignment: .trailing)
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .lineLimit(1)

            if !n.domainTag.isEmpty {
                Text(n.domainTag)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedOutlineNodeID = n.nodeID
            focusedNodeID = n.nodeID
        }
        .onTapGesture(count: 2) {
            openNodeDetail(n.nodeID)
        }
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.35, maximumDistance: 24)
                .onEnded { _ in
                    openNodeDetail(n.nodeID)
                }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                openNodeDetail(n.nodeID)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .tint(.blue)
        }
        .padding(.vertical, 0)
    }

    private func hasChildren(_ nodeID: String) -> Bool {
        outline.nodes.contains(where: { $0.parentNodeID == nodeID })
    }

    private func outlineProgressRatio(nodeID: String) -> Double {
        let scopedNodes = outline.nodes.filter { $0.outlineID == outlineID }
        let byID = Dictionary(uniqueKeysWithValues: scopedNodes.map { ($0.nodeID, $0) })
        let childrenByParent = Dictionary(grouping: scopedNodes, by: { $0.parentNodeID ?? "__ROOT__" })
        var memo: [String: Double] = [:]
        func ownProgressRatio(_ node: NJOutlineNodeRecord) -> Double? {
            let filter = outline.nodeFilter(nodeID: node.nodeID)
            if let pct = asInt64(filter["progress_pct"]) {
                return max(0, min(100, Double(pct))) / 100.0
            }
            if let pct = filter["progress_pct"] as? Double {
                return max(0, min(100, pct)) / 100.0
            }
            return nil
        }

        func progress(_ id: String) -> Double {
            if let cached = memo[id] { return cached }
            guard let node = byID[id] else { return 0 }
            if let own = ownProgressRatio(node) {
                memo[id] = own
                return own
            }
            let kids = childrenByParent[id] ?? []
            if !kids.isEmpty {
                let values = kids.map { progress($0.nodeID) }
                let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                memo[id] = avg
                return avg
            }
            let value: Double
            if node.isChecklist {
                value = node.isChecked ? 1 : 0
            } else {
                value = 0
            }
            memo[id] = value
            return value
        }

        return progress(nodeID)
    }

    private func applyGanttSiblingScheduleIfNeeded(fromSelectedNodeID selectedNodeID: String, toCreatedNodeID createdNodeID: String) {
        guard experimentalGanttMode else { return }
        let source = outline.nodeFilter(nodeID: selectedNodeID)
        guard let sourceEndMs = asInt64(source["end_ms"]) else { return }

        let dayMs: Int64 = 86_400_000
        let sourceStartMs = asInt64(source["start_ms"])
        let sourceStartDay = sourceStartMs.map { dayStartMs(Date(timeIntervalSince1970: TimeInterval($0) / 1000.0)) }
        let sourceEndDay = dayStartMs(Date(timeIntervalSince1970: TimeInterval(sourceEndMs) / 1000.0))
        let durationDays: Int64 = {
            guard let s = sourceStartDay else { return 1 }
            let days = ((sourceEndDay - s) / dayMs) + 1
            return max(days, 1)
        }()

        let newStartDay = sourceEndDay + dayMs
        let newStartDate = Date(timeIntervalSince1970: TimeInterval(newStartDay) / 1000.0)
        let newEndDay = newStartDay + dayMs * (durationDays - 1)
        let newEndDate = Date(timeIntervalSince1970: TimeInterval(newEndDay) / 1000.0)

        var target = outline.nodeFilter(nodeID: createdNodeID)
        target["start_ms"] = dayStartMs(newStartDate)
        target["end_ms"] = dayEndMs(newEndDate)
        outline.setNodeFilter(nodeID: createdNodeID, filter: target)
    }

    private func outlineRowScheduleColumns(nodeID: String) -> (start: String, end: String) {
        let filter = outline.nodeFilter(nodeID: nodeID)
        let start = asInt64(filter["start_ms"])
        let end = asInt64(filter["end_ms"])
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMd")
        func fmt(_ ms: Int64?) -> String {
            guard let ms else { return "-" }
            return f.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0))
        }
        return (fmt(start), fmt(end))
    }

    private var promotedMindmapRootID: String? {
        let roots = rows.filter { $0.node.parentNodeID == nil }
        guard roots.count == 1 else { return nil }
        let rootID = roots[0].node.nodeID
        let hasChildren = rows.contains { $0.node.parentNodeID == rootID }
        return hasChildren ? rootID : nil
    }

    private var mindmapRows: [NJOutlineNodeRow] {
        let filtered = filteredRowsForMindmapDate()
        guard let promoted = promotedMindmapRootID else { return rows }
        let valid = Set(filtered.map { $0.node.nodeID })
        if !valid.contains(promoted) {
            return filtered
        }
        return filtered.filter { $0.node.nodeID != promoted }
    }

    private func mindmapTopLevelNodeIDs(in sourceRows: [NJOutlineNodeRow]) -> [String] {
        if let promoted = promotedMindmapRootID {
            return sourceRows
                .filter { $0.node.parentNodeID == promoted }
                .map { $0.node.nodeID }
        }
        return sourceRows
            .filter { $0.node.parentNodeID == nil }
            .map { $0.node.nodeID }
    }

    private func mindElixirDataJSON() -> String {
        let allowedMindmapIDs = filteredNodeIDs(for: mindmapDateFilter)
        let scoped = outline.nodes
            .filter { $0.outlineID == outlineID && allowedMindmapIDs.contains($0.nodeID) }
            .sorted { a, b in
                if a.parentNodeID != b.parentNodeID {
                    return (a.parentNodeID ?? "") < (b.parentNodeID ?? "")
                }
                if a.ord != b.ord { return a.ord < b.ord }
                return a.createdAtMs < b.createdAtMs
            }

        let byParent = Dictionary(grouping: scoped, by: { $0.parentNodeID ?? "__ROOT__" })

        func topic(_ n: NJOutlineNodeRecord) -> String {
            let t = n.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Untitled" : t
        }

        func nodeObj(_ n: NJOutlineNodeRecord) -> [String: Any] {
            let kids = (byParent[n.nodeID] ?? []).sorted { $0.ord < $1.ord }
            var out: [String: Any] = [
                "id": n.nodeID,
                "topic": topic(n),
                "expanded": !n.isCollapsed
            ]
            if !kids.isEmpty {
                out["children"] = kids.map { nodeObj($0) }
            }
            return out
        }

        if let focusID = activeFocusNodeID,
           let focusNode = scoped.first(where: { $0.nodeID == focusID }) {
            let focusRoot = nodeObj(focusNode)
            let rootObj: [String: Any] = ["nodeData": focusRoot]
            guard let data = try? JSONSerialization.data(withJSONObject: rootObj),
                  let json = String(data: data, encoding: .utf8) else {
                return "{\"nodeData\":{\"id\":\"outline\",\"topic\":\"Outline\",\"expanded\":true,\"children\":[]}}"
            }
            return json
        }

        let rootsRaw = (byParent["__ROOT__"] ?? []).sorted { $0.ord < $1.ord }
        let topNodes: [NJOutlineNodeRecord] = {
            guard rootsRaw.count == 1, let root = rootsRaw.first else { return rootsRaw }
            let outlineTopic = outlineTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rootTopic = topic(root).lowercased()
            let shouldPromoteRoot = !outlineTopic.isEmpty && rootTopic == outlineTopic
            guard shouldPromoteRoot else { return rootsRaw }
            let rootKids = (byParent[root.nodeID] ?? []).sorted { $0.ord < $1.ord }
            return rootKids.isEmpty ? rootsRaw : rootKids
        }()

        let rootObj: [String: Any] = [
            "nodeData": [
                "id": "outline:\(outlineID)",
                "topic": outlineTitle,
                "expanded": true,
                "children": topNodes.map { nodeObj($0) }
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: rootObj),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"nodeData\":{\"id\":\"outline\",\"topic\":\"Outline\",\"expanded\":true,\"children\":[]}}"
        }
        return json
    }

    private func experimentalInkCanvas() -> some View {
        GeometryReader { geo in
            experimentalInkCanvasBody(geo: geo)
        }
    }

    @ViewBuilder
    private func experimentalInkCanvasBody(geo: GeometryProxy) -> some View {
        let panelSize = CGSize(width: 264, height: 228)
        let anchorOffset = CGPoint(x: 14, y: 14)
        let halfWidth = panelSize.width * 0.5
        let halfHeight = panelSize.height * 0.5
        let minCenterX = halfWidth + 8
        let minCenterY = halfHeight + 8
        let maxCenterX = max(geo.size.width - halfWidth - 8, minCenterX)
        let maxCenterY = max(geo.size.height - halfHeight - 8, minCenterY)
        let desiredCenterX = inkMenuAnchorPoint.x + anchorOffset.x + halfWidth
        let desiredCenterY = inkMenuAnchorPoint.y + anchorOffset.y + halfHeight
        let menuCenterX = min(max(desiredCenterX, minCenterX), maxCenterX)
        let menuCenterY = min(max(desiredCenterY, minCenterY), maxCenterY)

        NJOutlineMindElixirView(
                dataJSON: mindElixirDataJSON(),
                dataRevision: mindmapDataRevision(),
                selectedNodeID: store.selectedOutlineNodeID
            ) { event in
            switch event.kind {
            case .select:
                if let id = event.nodeID {
                    store.selectedOutlineNodeID = id
                }
            case .hover:
                if let p = event.point {
                    inkMenuAnchorPoint = p
                }
            case .contextMenu:
                if let id = event.nodeID {
                    store.selectedOutlineNodeID = id
                }
                presentInkNodeMenu(nodeID: event.nodeID, at: event.point)
            case .rename:
                if let id = event.nodeID, let topic = event.topic {
                    outline.updateNodeTitle(nodeID: id, title: topic)
                    requestImmediateCloudPush()
                }
            case .collapseToggle:
                if let id = event.nodeID {
                    outline.toggleCollapsed(nodeID: id)
                    requestImmediateCloudPush()
                }
            case .createChild:
                if let id = event.nodeID, let created = outline.createChildNode(nodeID: id) {
                    if let topic = event.topic, !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        outline.updateNodeTitle(nodeID: created.nodeID, title: topic)
                    }
                    store.selectedOutlineNodeID = created.nodeID
                    requestImmediateCloudPush()
                }
            case .createSibling:
                if let id = event.nodeID, let created = outline.createSiblingNode(nodeID: id) {
                    if let topic = event.topic, !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        outline.updateNodeTitle(nodeID: created.nodeID, title: topic)
                    }
                    store.selectedOutlineNodeID = created.nodeID
                    requestImmediateCloudPush()
                }
            case .move:
                if let id = event.nodeID {
                    var targetParent = event.toParentNodeID
                    if let p = targetParent, p.hasPrefix("outline:") {
                        if let focused = activeFocusNodeID {
                            targetParent = focused
                        } else if let promoted = promotedMindmapRootID {
                            targetParent = promoted
                        } else {
                            targetParent = nil
                        }
                    }
                    outline.moveNodeFromMindmap(
                        nodeID: id,
                        toParentNodeID: targetParent,
                        toIndex: event.toIndex ?? 0
                    )
                    requestImmediateCloudPush()
                }
            case .unknown:
                break
            }
        } onSqueeze: { point in
            if let selected = effectiveSelectedNodeID,
               rows.contains(where: { $0.node.nodeID == selected }) {
                inkMenuNodeID = selected
                store.selectedOutlineNodeID = selected
            } else if let first = rows.first?.node.nodeID {
                inkMenuNodeID = first
                store.selectedOutlineNodeID = first
            } else {
                inkMenuNodeID = nil
            }
            presentInkNodeMenu(nodeID: inkMenuNodeID, at: point)
        }
        .background(Color(UIColor.systemGray6))
        .overlay(alignment: .topLeading) {
            if showInkNodePopover {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { showInkNodePopover = false }
                    VStack(spacing: 0) {
                        inkNodePopoverContent()
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
                    .frame(width: panelSize.width)
                    .position(x: menuCenterX, y: menuCenterY)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .allowsHitTesting(true)
    }

    private func experimentalGanttCanvas() -> some View {
        NJOutlineFrappeGanttView(
            tasksJSON: frappeGanttTasksJSON(),
            revision: ganttDataRevision(),
            viewMode: ganttTimeScope.frappeViewMode
        ) { kind, payload in
            switch kind {
            case "select":
                if let id = payload["id"] as? String {
                    store.selectedOutlineNodeID = id
                    focusedNodeID = id
                    startEditingGanttTask(nodeID: id)
                }
            case "toggle_collapse":
                if let id = payload["id"] as? String {
                    let wantsOpen: Bool? = {
                        if let n = payload["open"] as? Int { return n != 0 }
                        if let b = payload["open"] as? Bool { return b }
                        return nil
                    }()
                    if let node = outline.node(id), let wantsOpen {
                        let shouldBeCollapsed = !wantsOpen
                        if node.isCollapsed != shouldBeCollapsed {
                            outline.toggleCollapsed(nodeID: id)
                            requestImmediateCloudPush()
                        }
                    } else {
                        outline.toggleCollapsed(nodeID: id)
                        requestImmediateCloudPush()
                    }
                }
            case "date_change":
                guard let id = payload["id"] as? String else { return }
                let start = asInt64(payload["start"])
                let endExclusive = asInt64(payload["end"])
                if start == nil && endExclusive == nil { return }
                let adjustedEnd = endExclusive.map { $0 > 0 ? ($0 - 1) : $0 }
                updateNodeScheduleFromGantt(nodeID: id, startMs: start, endMs: adjustedEnd)
            case "link_add", "link_update":
                guard let source = payload["source"] as? String,
                      let target = payload["target"] as? String else { return }
                addGanttDependency(sourceID: source, targetID: target)
            case "link_delete":
                guard let source = payload["source"] as? String,
                      let target = payload["target"] as? String else { return }
                removeGanttDependency(sourceID: source, targetID: target)
            default:
                break
            }
        }
        .background(Color(UIColor.systemGray6))
    }

    private func experimentalGanttWorkspace() -> some View {
        VStack(spacing: 0) {
            if ganttPlanningMode {
                ganttPlanningPanel()
                Divider()
            }
            experimentalGanttCanvas()
        }
    }

    private func ganttPlanningPanel() -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Planning Mode")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Showing active nodes in \(ganttTimeScope.title.lowercased()).")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            List {
                ForEach(Array(ganttPlanningRows().enumerated()), id: \.element.id) { idx, row in
                    ganttPlanningRow(row, idx: idx)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(rowBackground(idx: idx))
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 34)
        }
        .frame(minHeight: 200, idealHeight: 230, maxHeight: 260)
        .background(Color(UIColor.systemBackground))
    }

    private func ganttPlanningRows() -> [NJOutlineNodeRow] {
        rows.filter { row in
            let filter = outline.nodeFilter(nodeID: row.node.nodeID)
            let startMs = asInt64(filter["start_ms"])
            let endMs = asInt64(filter["end_ms"])
            guard let s = startMs ?? endMs, let e = endMs ?? startMs else { return false }
            return overlapsGanttScope(min(s, e), max(s, e))
        }
    }

    private func ganttPlanningRow(_ row: NJOutlineNodeRow, idx: Int) -> some View {
        let n = row.node
        let selected = (effectiveSelectedNodeID == n.nodeID)
        let scheduleText = ganttScheduleSummary(nodeID: n.nodeID)

        return HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(row.depth) * 12, height: 1)
            Circle()
                .fill(selected ? Color.accentColor : Color.clear)
                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: selected ? 0 : 1))
                .frame(width: 8, height: 8)
            Text(n.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : n.title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(scheduleText)
                .font(.system(size: 11))
                .foregroundColor(scheduleText == "No date" ? .secondary : .primary)
                .lineLimit(1)
            Button {
                store.selectedOutlineNodeID = n.nodeID
                focusedNodeID = n.nodeID
                startSchedulingMindmapNode(nodeID: n.nodeID)
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedOutlineNodeID = n.nodeID
            focusedNodeID = n.nodeID
        }
        .onTapGesture(count: 2) {
            startSchedulingMindmapNode(nodeID: n.nodeID)
        }
    }


    private func ganttDataRevision() -> Int {
        var h = Hasher()
        let scoped = outline.nodes.filter { $0.outlineID == outlineID }
        h.combine(scoped.count)
        for n in scoped.sorted(by: { $0.nodeID < $1.nodeID }) {
            h.combine(n.nodeID)
            h.combine(n.parentNodeID ?? "")
            h.combine(n.ord)
            h.combine(n.title)
            h.combine(n.filterJSON)
            h.combine(n.updatedAtMs)
        }
        h.combine(ganttTimeScope.rawValue)
        h.combine(ganttPlanningMode)
        return h.finalize()
    }

    private func frappeGanttTasksJSON() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        var tasks: [[String: Any]] = []
        let visibleNodes = ganttVisibleNodes()

        for item in visibleNodes {
            let node = item.node
            let startDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(item.displayStartMs) / 1000.0))
            var endDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(item.displayEndMs) / 1000.0))
            if endDate < startDate { endDate = startDate }
            if let plusOne = Calendar.current.date(byAdding: .day, value: 1, to: endDate) {
                endDate = plusOne
            }

            let base = node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : node.title
            var customClass = node.isChecklist && node.isChecked ? "nj-gantt-done" : ""
            if item.hasChildren {
                customClass = (customClass.isEmpty ? "" : customClass + " ") + "nj-gantt-group"
            }

            tasks.append([
                "id": node.nodeID,
                "name": base,
                "label_path": item.pathLabel,
                "parent_id": node.parentNodeID ?? "",
                "start": formatter.string(from: startDate),
                "end": formatter.string(from: endDate),
                "progress": ganttProgressPercent(nodeID: node.nodeID),
                "dependencies": ganttDependencies(nodeID: node.nodeID).joined(separator: ","),
                "custom_class": customClass,
                "depth": item.depth,
                "has_children": item.hasChildren,
                "is_collapsed": node.isCollapsed ? 1 : 0,
                "open": node.isCollapsed ? 0 : 1,
                "is_rollup": item.hasChildren && !item.hasOwnSchedule ? 1 : 0
            ])
        }

        if tasks.isEmpty {
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            tasks = [[
                "id": "placeholder",
                "name": "Add start/end date filters in node details to show items here",
                "label_path": "Add start/end date filters in node details to show items here",
                "start": formatter.string(from: today),
                "end": formatter.string(from: tomorrow),
                "progress": 0,
                "dependencies": "",
                "custom_class": "nj-gantt-placeholder"
            ]]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: tasks),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func ganttVisibleNodes() -> [GanttVisibleNode] {
        let scopedNodes = outline.nodes
            .filter { $0.outlineID == outlineID }
            .sorted {
                if ($0.parentNodeID ?? "") != ($1.parentNodeID ?? "") {
                    return ($0.parentNodeID ?? "") < ($1.parentNodeID ?? "")
                }
                if $0.ord != $1.ord { return $0.ord < $1.ord }
                return $0.createdAtMs < $1.createdAtMs
            }

        let byID = Dictionary(uniqueKeysWithValues: scopedNodes.map { ($0.nodeID, $0) })
        let childrenByParent = Dictionary(grouping: scopedNodes, by: { $0.parentNodeID ?? "__ROOT__" })

        var pathCache: [String: String] = [:]
        func pathLabel(for nodeID: String) -> String {
            if let cached = pathCache[nodeID] { return cached }
            var parts: [String] = []
            var cursor: String? = nodeID
            var guardCount = 0
            while let id = cursor, guardCount < 200 {
                guardCount += 1
                guard let n = byID[id] else { break }
                let t = n.title.trimmingCharacters(in: .whitespacesAndNewlines)
                parts.append(t.isEmpty ? "Untitled" : t)
                cursor = n.parentNodeID
            }
            let out = parts.reversed().joined(separator: "/")
            pathCache[nodeID] = out
            return out
        }

        var rollupCache: [String: (start: Int64, end: Int64, hasOwn: Bool)] = [:]
        func nodeOwnRange(_ n: NJOutlineNodeRecord) -> (Int64, Int64)? {
            let f = decodeFilterJSON(n.filterJSON)
            let s = asInt64(f["start_ms"])
            let e = asInt64(f["end_ms"])
            guard s != nil || e != nil else { return nil }
            let start = dayStartMs(Date(timeIntervalSince1970: TimeInterval((s ?? e ?? 0)) / 1000.0))
            let end = dayStartMs(Date(timeIntervalSince1970: TimeInterval((e ?? s ?? 0)) / 1000.0))
            return (min(start, end), max(start, end))
        }
        func rollup(for nodeID: String) -> (start: Int64, end: Int64, hasOwn: Bool)? {
            if let cached = rollupCache[nodeID] { return cached }
            guard let n = byID[nodeID] else { return nil }
            var minStart: Int64?
            var maxEnd: Int64?
            var hasOwn = false
            if let own = nodeOwnRange(n) {
                minStart = own.0
                maxEnd = own.1
                hasOwn = true
            }
            let kids = (childrenByParent[nodeID] ?? []).sorted { a, b in
                if a.ord != b.ord { return a.ord < b.ord }
                return a.createdAtMs < b.createdAtMs
            }
            for c in kids {
                if let r = rollup(for: c.nodeID) {
                    minStart = minStart.map { min($0, r.start) } ?? r.start
                    maxEnd = maxEnd.map { max($0, r.end) } ?? r.end
                }
            }
            guard let start = minStart, let end = maxEnd else { return nil }
            let out = (start: start, end: end, hasOwn: hasOwn)
            rollupCache[nodeID] = out
            return out
        }

        var out: [GanttVisibleNode] = []
        func appendVisible(parentID: String?, depth: Int) {
            let key = parentID ?? "__ROOT__"
            let kids = (childrenByParent[key] ?? []).sorted { a, b in
                if a.ord != b.ord { return a.ord < b.ord }
                return a.createdAtMs < b.createdAtMs
            }
            for n in kids {
                let hasChildren = !(childrenByParent[n.nodeID] ?? []).isEmpty
                if let r = rollup(for: n.nodeID) {
                    if overlapsGanttScope(r.start, r.end) {
                        out.append(GanttVisibleNode(
                            node: n,
                            depth: depth,
                            pathLabel: pathLabel(for: n.nodeID),
                            hasChildren: hasChildren,
                            displayStartMs: r.start,
                            displayEndMs: r.end,
                            hasOwnSchedule: r.hasOwn
                        ))
                    }
                }
                appendVisible(parentID: n.nodeID, depth: depth + 1)
            }
        }
        appendVisible(parentID: nil, depth: 0)
        return out
    }

    private func ganttScopeRange(reference now: Date = Date()) -> (startMs: Int64, endMs: Int64)? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        switch ganttTimeScope {
        case .monthly:
            let interval = cal.dateInterval(of: .month, for: day)
            return makeMsRange(interval)
        case .yearly:
            let interval = cal.dateInterval(of: .year, for: day)
            return makeMsRange(interval)
        case .quarterly:
            let month = cal.component(.month, from: day)
            let year = cal.component(.year, from: day)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = DateComponents()
            comps.year = year
            comps.month = quarterStartMonth
            comps.day = 1
            guard let start = cal.date(from: comps),
                  let endExclusive = cal.date(byAdding: .month, value: 3, to: start) else { return nil }
            return (
                Int64(start.timeIntervalSince1970 * 1000.0),
                Int64(endExclusive.timeIntervalSince1970 * 1000.0) - 1
            )
        }
    }

    private func overlapsGanttScope(_ startMs: Int64, _ endMs: Int64) -> Bool {
        guard let window = ganttScopeRange() else { return true }
        return !(endMs < window.startMs || startMs > window.endMs)
    }

    private func makeMsRange(_ interval: DateInterval?) -> (startMs: Int64, endMs: Int64)? {
        guard let interval else { return nil }
        return (
            Int64(interval.start.timeIntervalSince1970 * 1000.0),
            Int64(interval.end.timeIntervalSince1970 * 1000.0) - 1
        )
    }

    private func ganttVisibleScheduledRows() -> [NJOutlineNodeRow] {
        return rows.filter { row in
            let filter = outline.nodeFilter(nodeID: row.node.nodeID)
            let startMs = asInt64(filter["start_ms"])
            let endMs = asInt64(filter["end_ms"])
            guard startMs != nil || endMs != nil else { return false }
            return true
        }
    }

    private func mindmapDataRevision() -> Int {
        let allowed = filteredNodeIDs(for: mindmapDateFilter)
        let scoped = outline.nodes.filter { $0.outlineID == outlineID && allowed.contains($0.nodeID) }
        var h = Hasher()
        h.combine(scoped.count)
        for n in scoped.sorted(by: { $0.nodeID < $1.nodeID }) {
            h.combine(n.nodeID)
            h.combine(n.parentNodeID ?? "")
            h.combine(n.ord)
            h.combine(n.updatedAtMs)
            h.combine(n.isCollapsed)
            h.combine(n.title)
        }
        h.combine(activeFocusNodeID ?? "")
        h.combine(mindmapDateFilter.rawValue)
        return h.finalize()
    }

    private func requestImmediateCloudPush() {
        store.sync.schedulePush(debounceMs: 0)
    }

    private func filteredRowsForMindmapDate() -> [NJOutlineNodeRow] {
        filteredRows(for: mindmapDateFilter)
    }

    private func filteredRows(for dateFilter: MindmapDateFilter) -> [NJOutlineNodeRow] {
        let includeIDs = filteredNodeIDs(for: dateFilter)
        return rows.filter { includeIDs.contains($0.node.nodeID) }
    }

    private func filteredNodeIDs(for dateFilter: MindmapDateFilter) -> Set<String> {
        let scopedNodes = outline.nodes.filter { $0.outlineID == outlineID }
        guard dateFilter != .all else { return Set(scopedNodes.map(\.nodeID)) }
        guard let window = dateFilterRange(dateFilter) else { return Set(scopedNodes.map(\.nodeID)) }
        let byID = Dictionary(uniqueKeysWithValues: scopedNodes.map { ($0.nodeID, $0) })
        let childrenByParent = Dictionary(grouping: scopedNodes, by: { $0.parentNodeID ?? "__ROOT__" })

        func nodeDateRange(_ n: NJOutlineNodeRecord) -> (start: Int64, end: Int64)? {
            let f = decodeFilterJSON(n.filterJSON)
            let sRaw = asInt64(f["start_ms"])
            let eRaw = asInt64(f["end_ms"])
            guard sRaw != nil || eRaw != nil else { return nil }
            let start = dayStartMs(Date(timeIntervalSince1970: TimeInterval((sRaw ?? eRaw ?? 0)) / 1000.0))
            let end = dayStartMs(Date(timeIntervalSince1970: TimeInterval((eRaw ?? sRaw ?? 0)) / 1000.0))
            return (min(start, end), max(start, end))
        }

        func overlapsWindow(_ r: (start: Int64, end: Int64)) -> Bool {
            !(r.end < window.startMs || r.start > window.endMs)
        }

        var includeIDs = Set<String>()
        var cache: [String: Bool] = [:]
        func keep(_ nodeID: String) -> Bool {
            if let v = cache[nodeID] { return v }
            guard let n = byID[nodeID] else { cache[nodeID] = false; return false }
            if let r = nodeDateRange(n) {
                if overlapsWindow(r) {
                    includeIDs.insert(nodeID)
                    cache[nodeID] = true
                    return true
                } else {
                    cache[nodeID] = false
                    return false
                }
            }
            let kids = (childrenByParent[nodeID] ?? []).map(\.nodeID)
            let childMatch = kids.contains(where: keep)
            if childMatch { includeIDs.insert(nodeID) }
            cache[nodeID] = childMatch || nodeDateRange(n) == nil
            return cache[nodeID] ?? false
        }

        for n in scopedNodes {
            if nodeDateRange(n) == nil {
                includeIDs.insert(n.nodeID) // always keep undated nodes
                _ = keep(n.nodeID)          // also pull in descendant/ancestor links if needed
            } else if keep(n.nodeID) {
                includeIDs.insert(n.nodeID)
            }
        }

        // Keep undated ancestors for tree continuity, but do NOT re-include
        // dated ancestors that fall outside the active filter window.
        for n in scopedNodes where includeIDs.contains(n.nodeID) {
            var cursor = n.parentNodeID
            var guardCount = 0
            while let id = cursor, guardCount < 200 {
                guardCount += 1
                guard let ancestor = byID[id] else { break }
                if nodeDateRange(ancestor) == nil {
                    includeIDs.insert(id)
                    cursor = ancestor.parentNodeID
                } else {
                    break
                }
            }
        }
        return includeIDs
    }

    private func dateFilterRange(_ filter: MindmapDateFilter, reference now: Date = Date()) -> (startMs: Int64, endMs: Int64)? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        switch filter {
        case .all:
            return nil
        case .thisYear:
            return makeMsRange(cal.dateInterval(of: .year, for: day))
        case .thisQuarter:
            let month = cal.component(.month, from: day)
            let year = cal.component(.year, from: day)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = DateComponents()
            comps.year = year
            comps.month = quarterStartMonth
            comps.day = 1
            guard let start = cal.date(from: comps),
                  let endExclusive = cal.date(byAdding: .month, value: 3, to: start) else { return nil }
            return (
                Int64(start.timeIntervalSince1970 * 1000.0),
                Int64(endExclusive.timeIntervalSince1970 * 1000.0) - 1
            )
        case .thisMonth:
            return makeMsRange(cal.dateInterval(of: .month, for: day))
        case .thisDay:
            return makeMsRange(cal.dateInterval(of: .day, for: day))
        }
    }

    private func updateNodeScheduleFromGantt(nodeID: String, startMs: Int64?, endMs: Int64?) {
        var filter = outline.nodeFilter(nodeID: nodeID)
        if let startMs {
            filter["start_ms"] = startMs
        }
        if let endMs {
            filter["end_ms"] = endMs
        }
        outline.setNodeFilter(nodeID: nodeID, filter: filter)
        requestImmediateCloudPush()
    }

    private func ganttProgressPercent(nodeID: String) -> Double {
        let filter = outline.nodeFilter(nodeID: nodeID)
        if let p = asInt64(filter["progress_pct"]) {
            return max(0, min(100, Double(p)))
        }
        if let p = filter["progress_pct"] as? Double {
            return max(0, min(100, p))
        }
        if let n = outline.node(nodeID), n.isChecklist {
            return n.isChecked ? 100 : 0
        }
        return 0
    }

    private func startEditingGanttTask(nodeID: String) {
        guard outline.node(nodeID) != nil else { return }
        ganttTaskNodeID = nodeID
        ganttTaskProgressPct = ganttProgressPercent(nodeID: nodeID)
        showGanttTaskSheet = true
    }

    private func ganttTaskSheetTitle() -> String {
        guard let id = ganttTaskNodeID, let n = outline.node(id) else { return "Task" }
        let t = n.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Task" : t
    }

    private func saveGanttTaskProgress() {
        guard let id = ganttTaskNodeID else {
            showGanttTaskSheet = false
            return
        }
        let pct = Int64(max(0, min(100, Int(ganttTaskProgressPct.rounded()))))
        var filter = outline.nodeFilter(nodeID: id)
        filter["progress_pct"] = pct
        outline.setNodeFilter(nodeID: id, filter: filter)
        if let n = outline.node(id), n.isChecklist {
            if pct >= 100, !n.isChecked {
                outline.toggleChecked(nodeID: id)
            } else if pct < 100, n.isChecked {
                outline.toggleChecked(nodeID: id)
            }
        }
        requestImmediateCloudPush()
        showGanttTaskSheet = false
    }

    private func ganttDependencies(nodeID: String) -> [String] {
        let filter = outline.nodeFilter(nodeID: nodeID)
        if let arr = filter["depends_on"] as? [String] {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != nodeID }
        }
        if let arr = filter["dependencies"] as? [String] {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != nodeID }
        }
        if let csv = filter["dependencies"] as? String {
            return csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != nodeID }
        }
        return []
    }

    private func setGanttDependencies(nodeID: String, predecessors: [String]) {
        let cleaned = Array(Set(predecessors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != nodeID })).sorted()
        var filter = outline.nodeFilter(nodeID: nodeID)
        if cleaned.isEmpty {
            filter.removeValue(forKey: "depends_on")
            filter.removeValue(forKey: "dependencies")
        } else {
            filter["depends_on"] = cleaned
        }
        outline.setNodeFilter(nodeID: nodeID, filter: filter)
        requestImmediateCloudPush()
    }

    private func addGanttDependency(sourceID: String, targetID: String) {
        guard sourceID != targetID else { return }
        var deps = ganttDependencies(nodeID: targetID)
        if !deps.contains(sourceID) {
            deps.append(sourceID)
            setGanttDependencies(nodeID: targetID, predecessors: deps)
        }
    }

    private func removeGanttDependency(sourceID: String, targetID: String) {
        var deps = ganttDependencies(nodeID: targetID)
        deps.removeAll { $0 == sourceID }
        setGanttDependencies(nodeID: targetID, predecessors: deps)
    }

    private func decodeFilterJSON(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private func ganttScheduleSummary(nodeID: String) -> String {
        let filter = outline.nodeFilter(nodeID: nodeID)
        let start = asInt64(filter["start_ms"])
        let end = asInt64(filter["end_ms"])
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMd")

        func fmt(_ ms: Int64) -> String {
            f.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0))
        }

        switch (start, end) {
        case let (s?, e?):
            return "\(fmt(s)) - \(fmt(e))"
        case let (nil, e?):
            return "Due \(fmt(e))"
        case let (s?, nil):
            return "Start \(fmt(s))"
        default:
            return "No date"
        }
    }

    private func dayStartMs(_ d: Date) -> Int64 {
        let day = Calendar.current.startOfDay(for: d)
        return Int64(day.timeIntervalSince1970 * 1000.0)
    }

    private func dayEndMs(_ d: Date) -> Int64 {
        let start = Calendar.current.startOfDay(for: d)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? d
        return Int64(next.timeIntervalSince1970 * 1000.0) - 1
    }

    private func asInt64(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? Double { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String, let n = Int64(s) { return n }
        return nil
    }

    private func positionForInkNode(
        _ nodeID: String,
        depth: Int,
        index: Int,
        centerX: CGFloat,
        sourceRows: [NJOutlineNodeRow],
        defaults: [String: CGPoint]? = nil
    ) -> CGPoint {
        if let p = inkNodePositions[nodeID] {
            return p
        }
        if let defaults, let p = defaults[nodeID] {
            return p
        }
        let side = branchSide(forNodeID: nodeID, sourceRows: sourceRows)
        let xMag = depth == 0 ? 250 : 250 + (CGFloat(depth) * 170)
        let x = centerX + (side == .right ? xMag : -xMag)
        let y = 160 + CGFloat(index) * 92
        return CGPoint(x: x, y: y)
    }

    private func setInkPosition(for nodeID: String, point: CGPoint, save: Bool = true) {
        inkNodePositions[nodeID] = point
        if save { saveInkPositions() }
    }

    private func maybeCreateNodeFromStroke(_ value: DragGesture.Value) {
        let sx = value.startLocation.x / max(inkCanvasScale, 0.01)
        let sy = value.startLocation.y / max(inkCanvasScale, 0.01)
        let ex = value.location.x / max(inkCanvasScale, 0.01)
        let ey = value.location.y / max(inkCanvasScale, 0.01)
        let dx = ex - sx
        let dy = ey - sy
        let len = hypot(dx, dy)
        if len < 32 || len > 240 { return }
        if abs(dy) > abs(dx) * 0.65 { return }

        let node = outline.createRootNode(outlineID: outlineID)
        store.selectedOutlineNodeID = node.nodeID
        let center = CGPoint(
            x: (ex + sx) * 0.5,
            y: (ey + sy) * 0.5
        )
        setInkPosition(for: node.nodeID, point: center)
    }

    private func handlePencilSqueeze(at location: CGPoint, centerX: CGFloat) {
        let normalized = CGPoint(
            x: location.x / max(inkCanvasScale, 0.01),
            y: location.y / max(inkCanvasScale, 0.01)
        )
        if let hoveredNodeID = nodeID(at: normalized, centerX: centerX) {
            inkMenuNodeID = hoveredNodeID
            store.selectedOutlineNodeID = hoveredNodeID
        } else if let selected = store.selectedOutlineNodeID,
                  rows.contains(where: { $0.node.nodeID == selected }) {
            inkMenuNodeID = selected
        } else if let first = rows.first?.node.nodeID {
            inkMenuNodeID = first
            store.selectedOutlineNodeID = first
        } else {
            inkMenuNodeID = nil
        }
        presentInkNodeMenu(nodeID: inkMenuNodeID, at: normalized)
    }

    private func nodeID(at location: CGPoint, centerX: CGFloat) -> String? {
        // Hit test against the rendered card rects in canvas coordinates.
        let cardSize = CGSize(width: 260, height: 72)
        let sourceRows = mindmapRows
        let defaults = defaultInkPositions(centerX: centerX, centerY: 360, sourceRows: sourceRows)
        for (idx, row) in sourceRows.enumerated().reversed() {
            let p = positionForInkNode(
                row.node.nodeID,
                depth: row.depth,
                index: idx,
                centerX: centerX,
                sourceRows: sourceRows,
                defaults: defaults
            )
            let rect = CGRect(
                x: p.x - cardSize.width * 0.5,
                y: p.y - cardSize.height * 0.5,
                width: cardSize.width,
                height: cardSize.height
            )
            if rect.contains(location) {
                return row.node.nodeID
            }
        }
        return nil
    }

    private func connectorStartPoint(from parent: CGPoint, to child: CGPoint) -> CGPoint {
        let halfW: CGFloat = 110
        if child.x >= parent.x {
            return CGPoint(x: parent.x + halfW, y: parent.y)
        }
        return CGPoint(x: parent.x - halfW, y: parent.y)
    }

    private func connectorEndPoint(from parent: CGPoint, to child: CGPoint) -> CGPoint {
        let halfW: CGFloat = 110
        if child.x >= parent.x {
            return CGPoint(x: child.x - halfW, y: child.y)
        }
        return CGPoint(x: child.x + halfW, y: child.y)
    }

    private enum NJInkBranchSide {
        case left
        case right
    }

    private func branchSide(forNodeID nodeID: String, sourceRows: [NJOutlineNodeRow]) -> NJInkBranchSide {
        if sourceRows.isEmpty { return .right }

        let topLevel = mindmapTopLevelNodeIDs(in: sourceRows)
        if topLevel.isEmpty { return .right }

        let parentByNode: [String: String?] = Dictionary(
            uniqueKeysWithValues: sourceRows.map { ($0.node.nodeID, $0.node.parentNodeID) }
        )

        var cursor = nodeID
        var guardCount = 0
        while guardCount < 200 {
            guardCount += 1
            if topLevel.contains(cursor) {
                if let idx = topLevel.firstIndex(of: cursor) {
                    return idx.isMultiple(of: 2) ? .right : .left
                }
                break
            }
            guard let parent = parentByNode[cursor] ?? nil else { break }
            cursor = parent
        }
        return .right
    }

    private func defaultInkPositions(centerX: CGFloat, centerY: CGFloat, sourceRows: [NJOutlineNodeRow]) -> [String: CGPoint] {
        let rootSpacing: CGFloat = 180
        let childStepX: CGFloat = 150

        let topNodes = mindmapTopLevelNodeIDs(in: sourceRows)
        let rightRoots = topNodes.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        let leftRoots = topNodes.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)

        let byParent = Dictionary(grouping: sourceRows, by: { $0.node.parentNodeID ?? "__ROOT__" })
        var out: [String: CGPoint] = [:]

        func centeredOffset(index: Int, count: Int, spacing: CGFloat) -> CGFloat {
            (CGFloat(index) - CGFloat(max(count - 1, 0)) * 0.5) * spacing
        }

        func layoutBranch(nodeID: String, sideSign: CGFloat, level: Int) {
            let children = (byParent[nodeID] ?? []).map(\.node.nodeID)
            if children.isEmpty { return }
            let spread = max(78, 140 - CGFloat(level - 1) * 14)
            guard let parent = out[nodeID] else { return }
            for (idx, childID) in children.enumerated() {
                let y = parent.y + centeredOffset(index: idx, count: children.count, spacing: spread)
                let x = parent.x + sideSign * childStepX
                if out[childID] == nil {
                    out[childID] = CGPoint(x: x, y: y)
                }
                layoutBranch(nodeID: childID, sideSign: sideSign, level: level + 1)
            }
        }

        for (idx, id) in rightRoots.enumerated() {
            out[id] = CGPoint(
                x: centerX + 260,
                y: centerY + centeredOffset(index: idx, count: rightRoots.count, spacing: rootSpacing)
            )
            layoutBranch(nodeID: id, sideSign: 1, level: 1)
        }
        for (idx, id) in leftRoots.enumerated() {
            out[id] = CGPoint(
                x: centerX - 260,
                y: centerY + centeredOffset(index: idx, count: leftRoots.count, spacing: rootSpacing)
            )
            layoutBranch(nodeID: id, sideSign: -1, level: 1)
        }

        return out
    }

    private func startEditingInkNode(nodeID: String, title: String) {
        inkRenameNodeID = nodeID
        inkRenameDraft = title
        let filter = outline.nodeFilter(nodeID: nodeID)
        if let startMs = asInt64(filter["start_ms"]) {
            inkRenameStartEnabled = true
            inkRenameStartDate = Date(timeIntervalSince1970: TimeInterval(startMs) / 1000.0)
        } else {
            inkRenameStartEnabled = false
            inkRenameStartDate = Date()
        }
        if let endMs = asInt64(filter["end_ms"]) {
            inkRenameEndEnabled = true
            inkRenameEndDate = Date(timeIntervalSince1970: TimeInterval(endMs) / 1000.0)
        } else {
            inkRenameEndEnabled = false
            inkRenameEndDate = Date()
        }
        normalizeInkRenameDateRange()
        showInkRenameSheet = true
    }

    private func startSchedulingMindmapNode(nodeID: String) {
        mindmapScheduleNodeID = nodeID
        let filter = outline.nodeFilter(nodeID: nodeID)
        if let startMs = asInt64(filter["start_ms"]) {
            mindmapStartEnabled = true
            mindmapStartDate = Date(timeIntervalSince1970: TimeInterval(startMs) / 1000.0)
        } else {
            mindmapStartEnabled = false
            mindmapStartDate = Date()
        }
        if let endMs = asInt64(filter["end_ms"]) {
            mindmapEndEnabled = true
            mindmapEndDate = Date(timeIntervalSince1970: TimeInterval(endMs) / 1000.0)
        } else {
            mindmapEndEnabled = false
            mindmapEndDate = Date()
        }
        normalizeMindmapScheduleDateRange()
        showMindmapScheduleSheet = true
    }

    private func scheduleSheetTitle() -> String {
        guard let nodeID = mindmapScheduleNodeID,
              let n = outline.node(nodeID) else { return "Schedule" }
        let t = n.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Schedule" : t
    }

    private func normalizeInkRenameDateRange() {
        guard inkRenameStartEnabled else { return }
        if inkRenameEndEnabled && inkRenameEndDate < inkRenameStartDate {
            inkRenameEndDate = inkRenameStartDate
        }
    }

    private func normalizeMindmapScheduleDateRange() {
        guard mindmapStartEnabled else { return }
        if mindmapEndEnabled && mindmapEndDate < mindmapStartDate {
            mindmapEndDate = mindmapStartDate
        }
    }

    private func saveMindmapSchedule() {
        guard let nodeID = mindmapScheduleNodeID else {
            showMindmapScheduleSheet = false
            return
        }
        normalizeMindmapScheduleDateRange()
        var filter = outline.nodeFilter(nodeID: nodeID)
        if mindmapStartEnabled {
            filter["start_ms"] = dayStartMs(mindmapStartDate)
        } else {
            filter.removeValue(forKey: "start_ms")
        }
        if mindmapEndEnabled {
            filter["end_ms"] = dayEndMs(mindmapEndDate)
        } else {
            filter.removeValue(forKey: "end_ms")
        }
        outline.setNodeFilter(nodeID: nodeID, filter: filter)
        requestImmediateCloudPush()
        showMindmapScheduleSheet = false
    }

    private func inkPositionStoreKey() -> String {
        "nj.outline.ink.positions.\(outlineID)"
    }

    private func resetInkLayoutPersisted() {
        // Reset persisted canvas positions to avoid stale/off-screen layouts.
        inkNodePositions = [:]
        UserDefaults.standard.removeObject(forKey: inkPositionStoreKey())
    }

    private func saveInkPositions() {
        let payload: [String: [CGFloat]] = inkNodePositions.reduce(into: [:]) { partial, kv in
            partial[kv.key] = [kv.value.x, kv.value.y]
        }
        UserDefaults.standard.set(payload, forKey: inkPositionStoreKey())
    }

    private func pruneInkPositions() {
        let valid = Set(rows.map { $0.node.nodeID })
        inkNodePositions = inkNodePositions.filter { valid.contains($0.key) }
        saveInkPositions()
    }

    private func moveRows(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first,
              sourceIndex >= 0,
              sourceIndex < rows.count else { return }

        let moving = rows[sourceIndex].node
        let parentID = moving.parentNodeID
        let clampedDestination = min(max(destination, 0), rows.count)

        // Count same-parent rows before destination to derive insertion index
        // within the sibling set. Exclude the moving row itself.
        let siblingIndex = rows
            .prefix(clampedDestination)
            .filter { $0.node.parentNodeID == parentID && $0.node.nodeID != moving.nodeID }
            .count

        outline.reorderNodeWithinParent(nodeID: moving.nodeID, toSiblingIndex: siblingIndex)
        store.selectedOutlineNodeID = moving.nodeID
        focusedNodeID = moving.nodeID
    }

    private func openNodeDetail(_ nodeID: String) {
        store.selectedOutlineNodeID = nodeID
        focusedNodeID = nodeID
        if isIPhone {
            phoneDetailNodeID = nodeID
            showPhoneDetailSheet = true
        } else {
            openWindow(id: "outline-node-detail", value: nodeID)
        }
    }
}

private struct NJOutlineInkNodeCard: View {
    let title: String
    let hasChildren: Bool
    let isCollapsed: Bool
    let isSelected: Bool
    let onToggleCollapsed: () -> Void
    let onCreateChild: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if hasChildren {
                    Button {
                        onToggleCollapsed()
                    } label: {
                        Text(isCollapsed ? "+" : "-")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color(UIColor.systemBackground).opacity(0.96)))
                            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
                Text(title)
                    .font(.custom("BradleyHandITCTT-Bold", size: 22))
                    .lineLimit(3)
                Spacer(minLength: 0)
                Image(systemName: "hand.draw")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged(onDragChanged)
                            .onEnded(onDragEnded)
                    )
                Button {
                    onCreateChild()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground).opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 2 : 0)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
    }
}

#if os(iOS)
private struct NJPencilSqueezeCaptureView: UIViewRepresentable {
    let onSqueezeAt: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSqueezeAt: onSqueezeAt)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        if #available(iOS 17.5, *) {
            let interaction = UIPencilInteraction(delegate: context.coordinator)
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { }

    final class Coordinator: NSObject, UIPencilInteractionDelegate {
        private let onSqueezeAt: (CGPoint) -> Void

        init(onSqueezeAt: @escaping (CGPoint) -> Void) {
            self.onSqueezeAt = onSqueezeAt
        }

        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            guard squeeze.phase == .ended else { return }
            guard let pose = squeeze.hoverPose else { return }
            onSqueezeAt(pose.location)
        }
    }
}
#endif

#if os(iOS)
private struct NJOutlineFrappeGanttView: UIViewRepresentable {
    let tasksJSON: String
    let revision: Int
    let viewMode: String
    let onEvent: (String, [String: Any]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.add(context.coordinator, name: "ganttEvent")
        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.webView = web
        web.loadHTMLString(Self.htmlTemplate(tasksJSON: tasksJSON, viewMode: viewMode), baseURL: URL(string: "https://cdn.dhtmlx.com"))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.lastRevision != revision else { return }
        context.coordinator.lastRevision = revision
        let js = """
        window.__njGanttSetData && window.__njGanttSetData(\(tasksJSON), \(jsQuoted(viewMode)));
        """
        uiView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsQuoted(_ s: String) -> String {
        if let d = try? JSONSerialization.data(withJSONObject: [s]),
           let arr = String(data: d, encoding: .utf8),
           arr.count >= 2 {
            return String(arr.dropFirst().dropLast())
        }
        return "\"\""
    }

    static func htmlTemplate(tasksJSON: String, viewMode: String) -> String {
        let modeJSON: String = {
            if let d = try? JSONSerialization.data(withJSONObject: [viewMode]),
               let arr = String(data: d, encoding: .utf8),
               arr.count >= 2 {
                return String(arr.dropFirst().dropLast())
            }
            return "\"Day\""
        }()
        return """
        <!doctype html>
        <html>
        <head>
          <meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no'>
          <link rel='stylesheet' href='https://cdn.dhtmlx.com/gantt/edge/dhtmlxgantt.css'>
          <style>
            html, body { margin:0; padding:0; height:100%; background:#f2f2f4; }
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            #wrap { height:100%; display:flex; flex-direction:column; }
            #toolbar { display:none; gap:8px; padding:8px 10px; border-bottom:1px solid rgba(0,0,0,0.08); background: rgba(255,255,255,0.75); }
            #toolbar button { border:0; border-radius:8px; padding:6px 10px; background:#e8e8ed; font-size:12px; }
            #toolbar button.active { background:#cfe2ff; color:#0b57d0; }
            #gantt { flex:1; min-height:0; width:100%; }
            .nj-empty { padding: 14px; font-size: 12px; color: #666; }
            .dark body { background:#1c1c1e; }
            .dark #toolbar { background: rgba(28,28,30,0.85); border-bottom-color: rgba(255,255,255,0.12); }
            .dark #toolbar button { background:#2c2c2e; color:#f2f2f7; }
            .dark #toolbar button.active { background:#214f9a; color:#fff; }
            .gantt_grid_scale, .gantt_task_scale { font-size: 12px; }
            .gantt_row, .gantt_task_row { border-bottom-color: rgba(0,0,0,0.03) !important; }
            .gantt_row.odd, .gantt_task_row.odd { background: rgba(0,0,0,0.02); }
            .gantt_row, .gantt_task_row { background: transparent; }
            .gantt_tree_content { font-size: 11px; }
            .gantt_tree_content .nj-title { display:block; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; line-height:1.1; }
            .gantt_tree_content .nj-path { color:#666; font-size:10px; margin-top:1px; display:block; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; line-height:1.1; }
            .gantt_task_line { background:#8fb6ff; border-color:#6f9df6; }
            .gantt_task_progress { background:#e5484d !important; opacity:0.95; }
            .gantt_task_line.nj-gantt-done { background:#4caf50; border-color:#4caf50; }
            .gantt_task_line.nj-gantt-group { background:#dfe7ff; border-color:#9ab3ff; }
          </style>
        </head>
        <body>
          <div id='wrap'>
            <div id='toolbar'>
              <button data-mode='QuarterDay'>QD</button>
              <button data-mode='Week'>W</button>
              <button data-mode='Month'>M</button>
              <button data-mode='Day'>D</button>
            </div>
            <div id='gantt'></div>
          </div>
          <script src='https://cdn.dhtmlx.com/gantt/edge/dhtmlxgantt.js'></script>
          <script>
            (function(){
              const post = function(kind, payload){
                try { window.webkit?.messageHandlers?.ganttEvent?.postMessage({ kind, payload: payload || {} }); } catch (_) {}
              };
              let viewMode = \(modeJSON);
              let tasks = \(tasksJSON);
              const el = document.getElementById('gantt');
              const buttons = Array.from(document.querySelectorAll('#toolbar button'));
              let eventsBound = false;
              const getGantt = function() {
                return (window.gantt) || (window.dhtmlxgantt && window.dhtmlxgantt.gantt) || null;
              };
              const esc = function(v){
                return String(v == null ? '' : v)
                  .replace(/&/g, '&amp;')
                  .replace(/</g, '&lt;')
                  .replace(/>/g, '&gt;')
                  .replace(/\"/g, '&quot;')
                  .replace(/'/g, '&#39;');
              };

              function paintToolbar() {
                buttons.forEach(b => b.classList.toggle('active', b.dataset.mode === viewMode));
              }

              function normalize(list) {
                return (Array.isArray(list) ? list : []).map(t => ({
                  id: String(t.id),
                  text: String(t.name || 'Untitled'),
                  label_path: String(t.label_path || t.name || 'Untitled'),
                  parent: t.parent_id ? String(t.parent_id) : 0,
                  open: t.open === 0 ? false : true,
                  start_date: t.start,
                  end_date: t.end,
                  progress: Math.max(0, Math.min(1, Number(t.progress || 0) / 100)),
                  type: t.has_children ? 'project' : 'task',
                  readonly: false,
                  nj_class: t.custom_class || '',
                  has_children: !!t.has_children
                }));
              }

              function normalizeLinks(list) {
                const out = [];
                const seen = {};
                (Array.isArray(list) ? list : []).forEach((t) => {
                  const target = String(t.id || '');
                  if (!target) return;
                  const raw = t.dependencies;
                  const deps = String(raw == null ? '' : raw)
                    .split(',')
                    .map(s => s.trim())
                    .filter(Boolean);
                  deps.forEach((source) => {
                    if (!source || source === target) return;
                    const key = source + '->' + target;
                    if (seen[key]) return;
                    seen[key] = 1;
                    out.push({
                      id: key,
                      source: source,
                      target: target,
                      type: "0"
                    });
                  });
                });
                return out;
              }

              function applyScale(gantt, mode) {
                const weekDay = gantt.date.date_to_str('%D');
                const fmtDay = function(date){
                  return weekDay(date) + ' ' + (date.getMonth() + 1) + '/' + date.getDate();
                };
                const fmtHour = gantt.date.date_to_str('%H:%i');
                const fmtMonth = gantt.date.date_to_str('%F %Y');
                const fmtWeekStart = gantt.date.date_to_str('%d %M');
                gantt.config.scale_height = 56;
                if (mode === 'Day') {
                  gantt.config.min_column_width = 56;
                  gantt.config.scale_unit = 'day';
                  gantt.config.step = 1;
                  gantt.config.date_scale = '%D %m/%d';
                  gantt.config.subscales = [{ unit: 'hour', step: 6, date: '%H:%i' }];
                  gantt.config.scales = [
                    { unit: 'day', step: 1, format: function(date){ return fmtDay(date); } }
                  ];
                } else if (mode === 'Week') {
                  gantt.config.min_column_width = 90;
                  gantt.config.scale_unit = 'week';
                  gantt.config.step = 1;
                  gantt.config.date_scale = 'Week %W';
                  gantt.config.subscales = [];
                  gantt.config.scales = [
                    { unit: 'week', step: 1, format: function(date){
                        const week = gantt.date.date_to_str('%W')(date);
                        return 'Week ' + week;
                    }}
                  ];
                } else if (mode === 'Month') {
                  gantt.config.min_column_width = 120;
                  gantt.config.scale_unit = 'month';
                  gantt.config.step = 1;
                  gantt.config.date_scale = '%F %Y';
                  gantt.config.subscales = [];
                  gantt.config.scales = [
                    { unit: 'month', step: 1, format: function(date){ return fmtMonth(date); } }
                  ];
                } else { // QuarterDay
                  gantt.config.min_column_width = 70;
                  gantt.config.scale_unit = 'week';
                  gantt.config.step = 1;
                  gantt.config.date_scale = 'Week %W';
                  gantt.config.subscales = [{ unit: 'day', step: 1, date: '%D %j' }];
                  gantt.config.scales = [
                    { unit: 'week', step: 1, format: function(date){
                        const week = gantt.date.date_to_str('%W')(date);
                        return 'Week ' + week;
                    }},
                    { unit: 'day', step: 1, format: function(date){ return fmtDay(date); } }
                  ];
                }
              }

              function render() {
                paintToolbar();
                const gantt = getGantt();
                if (!gantt) {
                  el.innerHTML = "<div class='nj-empty'>DHTMLX Gantt failed to load</div>";
                  post('debug', { message: 'DHTMLX Gantt missing on window', hasNamespace: !!window.dhtmlxgantt, nsKeys: window.dhtmlxgantt ? Object.keys(window.dhtmlxgantt).slice(0,10) : [] });
                  return;
                }
                const safeTasks = normalize(tasks);
                if (!safeTasks.length) {
                  el.innerHTML = "<div class='nj-empty'>No scheduled nodes</div>";
                  return;
                }
                try {
                  gantt.config.xml_date = "%Y-%m-%d";
                  gantt.config.grid_width = 360;
                  gantt.config.grid_resize = true;
                  gantt.config.keep_grid_width = false;
                  gantt.config.grid_elastic_columns = "min_width";
                  gantt.config.min_grid_column_width = 120;
                  gantt.config.row_height = 42;
                  gantt.config.bar_height = 16;
                  gantt.config.drag_progress = false;
                  gantt.config.drag_resize = true;
                  gantt.config.drag_move = true;
                  gantt.config.drag_links = true;
                  gantt.config.readonly = false;
                  gantt.config.open_tree_initially = true;
                  gantt.config.columns = [
                    { name: "text", label: "Events", tree: true, width: "*", min_width: 180, max_width: 560, resize: true, template: function(task){
                        const txt = esc(task.text || "");
                        const path = esc(task.label_path || "");
                        return "<div style='padding-top:4px;height:34px;overflow:hidden'><span class='nj-title'>" + txt + "</span><span class='nj-path'>" + path + "</span></div>";
                    }},
                    { name: "start_date", label: "Start", align: "center", width: 78, min_width: 70, max_width: 140, resize: true },
                    { name: "end_date", label: "End", align: "center", width: 78, min_width: 70, max_width: 140, resize: true }
                  ];
                  applyScale(gantt, viewMode);
                  gantt.templates.task_class = function(start, end, task){ return task.nj_class || ""; };
                  if (!eventsBound) {
                    eventsBound = true;
                    gantt.attachEvent("onTaskSelected", function(id){ post('select', { id: String(id) }); return true; });
                    gantt.attachEvent("onTaskClick", function(id){ post('select', { id: String(id) }); return true; });
                    gantt.attachEvent("onAfterTaskDrag", function(id, mode, task){
                      post('date_change', {
                        id: String(id),
                        start: task && task.start_date ? task.start_date.getTime() : null,
                        end: task && task.end_date ? task.end_date.getTime() : null
                      });
                    });
                    gantt.attachEvent("onAfterLinkAdd", function(id, link){
                      post('link_add', {
                        id: String(id),
                        source: link && link.source ? String(link.source) : "",
                        target: link && link.target ? String(link.target) : "",
                        type: link && link.type != null ? String(link.type) : "0"
                      });
                    });
                    gantt.attachEvent("onAfterLinkUpdate", function(id, link){
                      post('link_update', {
                        id: String(id),
                        source: link && link.source ? String(link.source) : "",
                        target: link && link.target ? String(link.target) : "",
                        type: link && link.type != null ? String(link.type) : "0"
                      });
                    });
                    gantt.attachEvent("onAfterLinkDelete", function(id, link){
                      post('link_delete', {
                        id: String(id),
                        source: link && link.source ? String(link.source) : "",
                        target: link && link.target ? String(link.target) : "",
                        type: link && link.type != null ? String(link.type) : "0"
                      });
                    });
                    gantt.attachEvent("onTaskOpened", function(id){ post('toggle_collapse', { id: String(id), open: 1 }); });
                    gantt.attachEvent("onTaskClosed", function(id){ post('toggle_collapse', { id: String(id), open: 0 }); });
                  }
                  if (!gantt.$container || gantt.$container !== el) {
                    gantt.init(el);
                  }
                  const currentScroll = (gantt.getScrollState && gantt.getScrollState()) || { x: 0, y: 0 };
                  const safeLinks = normalizeLinks(tasks);
                  gantt.clearAll();
                  gantt.parse({ data: safeTasks, links: safeLinks });
                  if (gantt.resetLayout) { try { gantt.resetLayout(); } catch (_) {} }
                  if (gantt.render) gantt.render();
                  if (gantt.scrollTo) gantt.scrollTo(currentScroll.x || 0, currentScroll.y || 0);
                  post('debug', { message: 'DHTMLX Gantt booted', count: safeTasks.length, links: safeLinks.length, viewMode: viewMode, scales: (gantt.config.scales || []).map(function(s){ return s.unit; }) });
                } catch (e) {
                  el.innerHTML = "<div class='nj-empty'>Gantt render error</div>";
                  post('debug', { message: 'DHTMLX Gantt init failed', error: String((e && e.message) || e) });
                }
              }

              buttons.forEach(btn => btn.addEventListener('click', function() {
                viewMode = btn.dataset.mode || 'Day';
                render();
              }));

              window.__njGanttSetData = function(nextTasks, nextViewMode) {
                tasks = nextTasks;
                if (nextViewMode) viewMode = nextViewMode;
                render();
              };

              render();
            })();
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var lastRevision: Int = Int.min
        private let onEvent: (String, [String: Any]) -> Void

        init(onEvent: @escaping (String, [String: Any]) -> Void) {
            self.onEvent = onEvent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any],
               let kind = body["kind"] as? String,
               let payload = body["payload"] as? [String: Any] {
                onEvent(kind, payload)
                print("NJ_GANTT_DEBUG kind=\(kind) payload=\(payload)")
            } else {
                print("NJ_GANTT_DEBUG raw=\(message.body)")
            }
        }
    }
}

private struct NJOutlineMindElixirEvent {
    enum Kind {
        case select
        case hover
        case contextMenu
        case rename
        case collapseToggle
        case createChild
        case createSibling
        case move
        case unknown
    }
    var kind: Kind
    var nodeID: String?
    var topic: String?
    var toParentNodeID: String?
    var toIndex: Int?
    var point: CGPoint?
}

private struct NJOutlineMindElixirView: UIViewRepresentable {
    let dataJSON: String
    let dataRevision: Int
    let selectedNodeID: String?
    let onEvent: (NJOutlineMindElixirEvent) -> Void
    let onSqueeze: ((CGPoint?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent, onSqueeze: onSqueeze)
    }

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.add(context.coordinator, name: "mindEvent")

        let jsText = loadBundledTextFile(name: "mind-elixir", ext: "js")
        let cssText = loadBundledTextFile(name: "style", ext: "css")
        print("NJ_MIND_ASSET_BYTES js=\(jsText.utf8.count) css=\(cssText.utf8.count)")

        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        context.coordinator.webView = view
        let hoverGR = UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleNativeHover(_:)))
        hoverGR.cancelsTouchesInView = false
        view.addGestureRecognizer(hoverGR)
        if #available(iOS 17.5, *) {
            view.addInteraction(UIPencilInteraction(delegate: context.coordinator))
        }
        let jsBase64 = Data(jsText.utf8).base64EncodedString()
        let cssBase64 = Data(cssText.utf8).base64EncodedString()
        let html = Self.htmlTemplate(
            initialJSON: dataJSON,
            jsBase64Literal: Self.jsonStringLiteral(jsBase64),
            cssBase64Literal: Self.jsonStringLiteral(cssBase64)
        )
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastDataRevision != dataRevision {
            context.coordinator.lastDataRevision = dataRevision
            uiView.evaluateJavaScript("""
            (function(){
              try {
                if (window.__njSetData) { window.__njSetData(\(dataJSON)); }
              } catch (e) {
                try {
                  window.webkit.messageHandlers.mindEvent.postMessage({
                    type: 'debug',
                    payload: { message: 'setData failed', error: String((e && e.message) || e) }
                  });
                } catch (_) {}
              }
            })();
            """)
        }
        if let selectedNodeID {
            if context.coordinator.lastSelectedNodeID != selectedNodeID {
                context.coordinator.lastSelectedNodeID = selectedNodeID
                uiView.evaluateJavaScript("""
                (function(){
                  try {
                    if (window.__njSelectNode) { window.__njSelectNode('\(selectedNodeID)'); }
                  } catch (e) {
                    try {
                      window.webkit.messageHandlers.mindEvent.postMessage({
                        type: 'debug',
                        payload: { message: 'selectNode failed', error: String((e && e.message) || e) }
                      });
                    } catch (_) {}
                  }
                })();
                """)
            }
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "mindEvent")
    }

    static func htmlTemplate(initialJSON: String, jsBase64Literal: String, cssBase64Literal: String) -> String {
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
          <style>
            html,body,#map{margin:0;padding:0;width:100%;height:100%;background:#f6f7fb;overflow:hidden}
            #err{position:fixed;left:10px;top:10px;right:10px;padding:8px 10px;border-radius:8px;background:#fee;color:#900;font:12px -apple-system,system-ui;display:none;z-index:9999}
            .mind-elixir-toolbar.rb{display:none !important}
          </style>
        </head>
        <body>
          <div id="err"></div>
          <div id="map"></div>
          <script>
            const __mindJSBase64 = \(jsBase64Literal);
            const __mindCSSBase64 = \(cssBase64Literal);
            const errEl = document.getElementById('err');
            const showErr = (msg) => {
              if (!errEl) return;
              errEl.style.display = 'block';
              errEl.textContent = msg;
            };
            const post = (type, payload) => {
              try { window.webkit.messageHandlers.mindEvent.postMessage({type, payload}); } catch (_) {}
            };
            window.onerror = (msg, src, line, col) => {
              showErr('Mindmap error: ' + msg + ' @' + line + ':' + col);
              post('debug', { message: String(msg || ''), line, col, src: String(src || '') });
            };
            try {
              const style = document.createElement('style');
              style.textContent = atob(__mindCSSBase64 || '');
              document.head.appendChild(style);
            } catch (e) {
              post('debug', { message: 'MindElixir css inject failed', error: String((e && e.message) || e) });
            }
            try {
              const src = atob(__mindJSBase64 || '');
              (0, eval)('var module=undefined;var exports=undefined;var define=undefined;\\n' + src + '\\n//# sourceURL=mind-elixir-inline.js');
            } catch (e) {
              showErr('MindElixir script eval failed');
              post('debug', { message: 'MindElixir script eval failed', error: String((e && e.message) || e) });
            }
            try {
              if (!window.MindElixir && typeof MindElixir !== 'undefined') {
                window.MindElixir = MindElixir;
              }
            } catch (_) {}
            if (!window.MindElixir) {
              try {
                if (typeof module !== 'undefined' && module && module.exports) {
                  window.MindElixir = module.exports.default || module.exports;
                }
              } catch (_) {}
              try {
                if (!window.MindElixir && typeof exports !== 'undefined' && exports && exports.MindElixir) {
                  window.MindElixir = exports.MindElixir;
                }
              } catch (_) {}
            }
            const getMindCtor = () => {
              const m = window.MindElixir;
              if (!m) return null;
              if (typeof m === 'function') return m;
              if (m.default && typeof m.default === 'function') return m.default;
              if (m.MindElixir && typeof m.MindElixir === 'function') return m.MindElixir;
              return null;
            };
            post('debug', {
              message: 'MindElixir global probe',
              exists: !!window.MindElixir,
              type: typeof window.MindElixir
            });
            let mind = null;
            function boot(data){
              post('debug', { message: 'boot start', hasData: !!data, hasNodeData: !!(data && data.nodeData) });
              const MindCtor = getMindCtor();
              if (!MindCtor) {
                showErr('MindElixir failed to load');
                post('debug', { message: 'MindElixir missing on window' });
                return;
              }
              try {
                const side = MindCtor.SIDE || (window.MindElixir && window.MindElixir.SIDE) || 2;
                mind = new MindCtor({
                  el: document.getElementById('map'),
                  editable: true,
                  direction: side,
                  draggable: true,
                  contextMenu: true,
                  toolBar: true,
                  keypress: true,
                  allowUndo: true
                });
                mind.init(data);
                try {
                  const m = window.MindElixir || {};
                  const plugins = [m.nodeDraggable, m.draggablePlugin, m.nodeMenu, m.keypress];
                  plugins.forEach((p) => {
                    if (p && mind.install) {
                      try { mind.install(p); } catch (_) {}
                    }
                  });
                } catch (_) {}
              } catch (e) {
                showErr('MindElixir init failed');
                post('debug', { message: 'MindElixir init failed', error: String((e && e.message) || e) });
                return;
              }
              bind();
              post('debug', { message: 'MindElixir booted' });
            }
            function bind(){
              if (!mind || !mind.bus) return;
              const slimObj = (obj) => {
                if (!obj || typeof obj !== 'object') return null;
                const parent = obj.parent;
                let parentID = null;
                if (typeof parent === 'string') parentID = parent;
                else if (parent && typeof parent === 'object' && parent.id) parentID = parent.id;
                return {
                  id: obj.id || null,
                  topic: obj.topic || '',
                  index: (typeof obj.index === 'number') ? obj.index : null,
                  ord: (typeof obj.ord === 'number') ? obj.ord : null,
                  parent: parentID
                };
              };
              const beginEditByID = (id) => {
                if (!id || !mind) return;
                if (document.getElementById('input-box')) return;
                try {
                  const nodeEl = mind.findEle ? mind.findEle(id) : null;
                  if (!nodeEl) return;
                  if (mind.selectNode) mind.selectNode(nodeEl);
                  if (mind.beginEdit) {
                    mind.beginEdit(nodeEl);
                    return;
                  }
                  if (mind.editTopic) {
                    mind.editTopic(nodeEl);
                  }
                } catch (e) {
                  post('debug', { message: 'beginEdit failed', error: String((e && e.message) || e) });
                }
              };
              let editLockUntil = 0;
              const maybeBeginEditByID = (id) => {
                const now = Date.now();
                if (now < editLockUntil) return;
                if (document.getElementById('input-box')) return;
                beginEditByID(id);
                editLockUntil = now + 450;
              };
              let lastSelectIDRef = { value: null };
              const onSelect = (payload) => {
                let node = payload;
                if (Array.isArray(payload)) node = payload[0];
                const id = node && node.id ? node.id : null;
                post('select', { id: id });
                lastSelectIDRef.value = id;
              };
              mind.bus.addListener('selectNodes', onSelect);
              mind.bus.addListener('selectNewNode', onSelect);
              mind.bus.addListener('selectNode', onSelect);
              mind.bus.addListener('expandNode', (node) => {
                post('operation', { name: 'expandNode', obj: slimObj(node) });
              });
              mind.bus.addListener('operation', (op) => {
                const safe = {
                  name: (op && op.name) ? op.name : '',
                  type: (op && op.type) ? op.type : '',
                  index: (op && typeof op.index === 'number') ? op.index : null,
                  toParent: (op && op.toParent && op.toParent.id) ? op.toParent.id : null,
                  obj: slimObj(op ? op.obj : null),
                  objs: Array.isArray(op && op.objs) ? op.objs.map((v) => slimObj(v)).filter(Boolean) : null
                };
                post('debug', { message: 'op', name: safe.name, type: safe.type, id: safe.obj ? safe.obj.id : null, parent: safe.obj ? safe.obj.parent : null, idx: safe.index });
                post('operation', safe);
              });

              // iPad touch does not reliably emit native dblclick for custom elements.
              // Emulate double-tap to enter inline edit mode.
              let lastTapNodeID = null;
              let lastTapAt = 0;
              const nodeFromTarget = (target) => {
                let el = target;
                while (el && el !== document.body) {
                  if (el.nodeObj && el.nodeObj.id) return el;
                  el = el.parentElement;
                }
                return null;
              };
              const beginEdit = (nodeEl) => {
                if (!nodeEl) return;
                const id = nodeEl.nodeObj && nodeEl.nodeObj.id ? nodeEl.nodeObj.id : null;
                maybeBeginEditByID(id);
              };
              const tapHandler = (ev) => {
                if (!ev || !ev.changedTouches) return;
                const nodeEl = nodeFromTarget(ev.target);
                if (!nodeEl || !nodeEl.nodeObj || !nodeEl.nodeObj.id) return;
                const id = nodeEl.nodeObj.id;
                const now = Date.now();
                if (lastTapNodeID === id && (now - lastTapAt) < 360) {
                  beginEdit(nodeEl);
                }
                lastTapNodeID = id;
                lastTapAt = now;
              };
              const pointerHandler = (ev) => {
                if (!ev || ev.pointerType !== 'touch') return;
                const nodeEl = nodeFromTarget(ev.target);
                if (!nodeEl || !nodeEl.nodeObj || !nodeEl.nodeObj.id) return;
                const id = nodeEl.nodeObj.id;
                const now = Date.now();
                if (lastTapNodeID === id && (now - lastTapAt) < 360) {
                  beginEdit(nodeEl);
                }
                lastTapNodeID = id;
                lastTapAt = now;
              };
              const dblHandler = (ev) => {
                const nodeEl = nodeFromTarget(ev.target);
                const id = (nodeEl && nodeEl.nodeObj && nodeEl.nodeObj.id) ? nodeEl.nodeObj.id : lastSelectIDRef.value;
                maybeBeginEditByID(id);
              };
              const contextHandler = (ev) => {
                const nodeEl = nodeFromTarget(ev.target);
                const id = (nodeEl && nodeEl.nodeObj && nodeEl.nodeObj.id) ? nodeEl.nodeObj.id : lastSelectIDRef.value;
                if (!id) return;
                if (ev && ev.preventDefault) ev.preventDefault();
                post('context_menu', { id: id, x: ev && typeof ev.clientX === 'number' ? ev.clientX : null, y: ev && typeof ev.clientY === 'number' ? ev.clientY : null });
              };
              let hoverPostAt = { value: 0 };
              const hoverHandler = (ev) => {
                if (!ev) return;
                const now = Date.now();
                if ((now - hoverPostAt.value) < 8) return;
                hoverPostAt.value = now;
                if (typeof ev.clientX !== 'number' || typeof ev.clientY !== 'number') return;
                post('hover', { x: ev.clientX, y: ev.clientY });
              };
              if (mind.map) {
                mind.map.addEventListener('touchend', tapHandler, { passive: true });
                mind.map.addEventListener('dblclick', dblHandler, { passive: true });
                mind.map.addEventListener('contextmenu', contextHandler);
                mind.map.addEventListener('pointermove', hoverHandler, { passive: true });
                mind.map.addEventListener('mousemove', hoverHandler, { passive: true });
              }
              if (mind.container) {
                mind.container.addEventListener('dblclick', dblHandler, { passive: true });
                mind.container.addEventListener('contextmenu', contextHandler);
                mind.container.addEventListener('pointermove', hoverHandler, { passive: true });
              }
            }
            window.__njSetData = function(data){
              if (!mind) { boot(data); return; }
              try {
                mind.refresh(data);
              } catch (_) {
                try {
                  const prev = mind;
                  if (prev && prev.destroy) prev.destroy();
                  mind = null;
                  boot(data);
                } catch (e) {
                  showErr('refresh failed');
                }
              }
            };
            window.__njSelectNode = function(id){
              if (!mind || !id) return;
              if (document.getElementById('input-box')) return;
              try {
                const n = mind.findEle ? mind.findEle(id) : null;
                if (n && mind.selectNode) mind.selectNode(n);
              } catch (e) {
                post('debug', { message: 'selectNode failed', error: String((e && e.message) || e) });
              }
            };
            document.addEventListener('DOMContentLoaded', () => {
              const initial = \(initialJSON);
              boot(initial);
            });
          </script>
        </body>
        </html>
        """
    }

    private func loadBundledTextFile(name: String, ext: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return ""
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
           let raw = String(data: data, encoding: .utf8),
           raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        return "\"\""
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onEvent: (NJOutlineMindElixirEvent) -> Void
        let onSqueeze: ((CGPoint?) -> Void)?
        weak var webView: WKWebView?
        var lastDataRevision: Int = -1
        var lastSelectedNodeID: String? = nil
        var lastNativeHoverPoint: CGPoint? = nil
        var didOpenSqueezeMenuInCurrentGesture = false
        init(
            onEvent: @escaping (NJOutlineMindElixirEvent) -> Void,
            onSqueeze: ((CGPoint?) -> Void)?
        ) {
            self.onEvent = onEvent
            self.onSqueeze = onSqueeze
        }

        @objc func handleNativeHover(_ recognizer: UIHoverGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed,
                  let sourceView = recognizer.view else { return }
            let localPoint: CGPoint = {
                if let webView { return recognizer.location(in: webView) }
                return recognizer.location(in: sourceView)
            }()
            // Keep as a fallback only. Native hover coordinates can drift relative to the
            // transformed mindmap canvas; web pointer hover is more accurate for menu anchoring.
            lastNativeHoverPoint = localPoint
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mindEvent",
                  let raw = message.body as? [String: Any],
                  let type = raw["type"] as? String else { return }

            if type == "select" {
                let payload = raw["payload"] as? [String: Any]
                onEvent(NJOutlineMindElixirEvent(kind: .select, nodeID: payload?["id"] as? String))
                return
            }

            if type == "hover" {
                let payload = raw["payload"] as? [String: Any]
                let x = payload?["x"] as? Double
                let y = payload?["y"] as? Double
                let point: CGPoint? = {
                    guard let x, let y else { return nil }
                    return CGPoint(x: x, y: y)
                }()
                onEvent(NJOutlineMindElixirEvent(kind: .hover, point: point))
                return
            }

            if type == "context_menu" {
                let payload = raw["payload"] as? [String: Any]
                let x = payload?["x"] as? Double
                let y = payload?["y"] as? Double
                let point: CGPoint? = {
                    guard let x, let y else { return nil }
                    return CGPoint(x: x, y: y)
                }()
                onEvent(NJOutlineMindElixirEvent(kind: .contextMenu, nodeID: payload?["id"] as? String, point: point))
                return
            }

            if type == "debug" {
                if let payload = raw["payload"] as? [String: Any] {
                    print("NJ_MIND_DEBUG", payload)
                } else {
                    print("NJ_MIND_DEBUG", raw)
                }
                return
            }

            guard type == "operation",
                  let payload = raw["payload"] as? [String: Any] else {
                onEvent(NJOutlineMindElixirEvent(kind: .unknown))
                return
            }

            let name = ((payload["name"] as? String) ?? "").lowercased()
            let obj = toDict(payload["obj"])
            let objs = toDictArray(payload["objs"])
            let primaryObj = obj ?? objs?.first
            let id = (primaryObj?["id"] as? String) ?? (payload["id"] as? String)

            if name.contains("finish") || name.contains("edit") || name.contains("rename") {
                let topic = (primaryObj?["topic"] as? String) ?? (payload["topic"] as? String)
                onEvent(NJOutlineMindElixirEvent(kind: .rename, nodeID: id, topic: topic))
            } else if name.contains("expand") || name.contains("collapse") {
                onEvent(NJOutlineMindElixirEvent(kind: .collapseToggle, nodeID: id))
            } else if name.contains("move") || name.contains("drag") || name.contains("reshape") {
                let parentFromObj: String? = {
                    if let p = primaryObj?["parent"] as? String { return p }
                    if let p = toDict(primaryObj?["parent"]) { return p["id"] as? String }
                    return nil
                }()
                let parent = (payload["toParent"] as? String) ?? parentFromObj
                let idx = (payload["index"] as? Int) ?? (primaryObj?["index"] as? Int) ?? (primaryObj?["ord"] as? Int)
                print("NJ_MIND_MOVE name=\(name) id=\(id ?? "nil") parent=\(parent ?? "nil") idx=\(idx ?? -1)")
                onEvent(NJOutlineMindElixirEvent(kind: .move, nodeID: id, toParentNodeID: parent, toIndex: idx))
            } else if name.contains("insertsibling") {
                let topic = (primaryObj?["topic"] as? String) ?? ""
                onEvent(NJOutlineMindElixirEvent(kind: .createSibling, nodeID: id, topic: topic))
            } else if name.contains("addchild") {
                let topic = (primaryObj?["topic"] as? String) ?? ""
                onEvent(NJOutlineMindElixirEvent(kind: .createChild, nodeID: id, topic: topic))
            } else {
                onEvent(NJOutlineMindElixirEvent(kind: .unknown))
            }
        }

        private func toDict(_ any: Any?) -> [String: Any]? {
            if let d = any as? [String: Any] { return d }
            if let d = any as? NSDictionary {
                var out: [String: Any] = [:]
                d.forEach { key, value in
                    if let k = key as? String { out[k] = value }
                }
                return out
            }
            return nil
        }

        private func toDictArray(_ any: Any?) -> [[String: Any]]? {
            if let arr = any as? [[String: Any]] { return arr }
            if let arr = any as? [Any] {
                let mapped = arr.compactMap { toDict($0) }
                return mapped.isEmpty ? nil : mapped
            }
            if let arr = any as? NSArray {
                let mapped = arr.compactMap { toDict($0) }
                return mapped.isEmpty ? nil : mapped
            }
            return nil
        }
    }
}

extension NJOutlineMindElixirView.Coordinator: UIPencilInteractionDelegate {
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        // Prefer continuously tracked native hover location (screen-space accurate).
        // squeeze.hoverPose can report a different coordinate space and drifts when the
        // web canvas is transformed/zoomed.
        let fallbackNativePoint = lastNativeHoverPoint ?? {
            guard let rawPoint = squeeze.hoverPose?.location,
                  let sourceView = interaction.view else { return nil }
            if let webView {
                return sourceView.convert(rawPoint, to: webView)
            }
            return rawPoint
        }()
        if let fallbackNativePoint { lastNativeHoverPoint = fallbackNativePoint }

        switch squeeze.phase {
        case .began:
            didOpenSqueezeMenuInCurrentGesture = true
            // Anchor to the latest web hover point (already stored in SwiftUI state via .hover).
            // Passing nil preserves that anchor and avoids native-hover drift.
            onSqueeze?(nil)
        case .changed:
            break
        case .ended:
            if !didOpenSqueezeMenuInCurrentGesture {
                onSqueeze?(nil)
            }
            didOpenSqueezeMenuInCurrentGesture = false
        default:
            break
        }
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        // Fallback trigger for non‑Pencil‑Pro hardware (double-tap gesture).
        onSqueeze?(nil)
    }
}

private struct NJOutlineHandwritingSheet: View {
    enum Action {
        case replaceSelected
        case appendSelected
        case newChild
    }

    @Environment(\.dismiss) private var dismiss
    let onInsert: (Action, String) -> Void

    @State private var drawing = PKDrawing()
    @State private var recognizedText: String = ""
    @State private var isRecognizing = false
    @State private var recognizeChinese = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                NJOutlinePencilCanvas(drawing: $drawing)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(UIColor.separator), lineWidth: 0.6)
                    )
                    .padding(12)

                TextEditor(text: $recognizedText)
                    .font(.system(size: 14))
                    .frame(minHeight: 90, maxHeight: 140)
                    .padding(.horizontal, 12)

                HStack {
                    Button("Recognize") { recognize() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRecognizing)
                    Button(recognizeChinese ? "中文" : "EN") {
                        recognizeChinese.toggle()
                    }
                    .buttonStyle(.bordered)
                    Button("Clear") {
                        drawing = PKDrawing()
                        recognizedText = ""
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal, 12)

                HStack(spacing: 8) {
                    Button("Replace") {
                        onInsert(.replaceSelected, recognizedText)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Append") {
                        onInsert(.appendSelected, recognizedText)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("New Child") {
                        onInsert(.newChild, recognizedText)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .navigationTitle("Handwriting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func recognize() {
        isRecognizing = true
        let image = drawing.image(from: drawing.bounds.isNull ? CGRect(x: 0, y: 0, width: 1200, height: 800) : drawing.bounds, scale: 2)
        guard let cg = image.cgImage else {
            isRecognizing = false
            return
        }
        let req = VNRecognizeTextRequest { req, _ in
            let text = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
                ?? ""
            DispatchQueue.main.async {
                recognizedText = text
                isRecognizing = false
            }
        }
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = recognizeChinese ? ["zh-Hans", "zh-Hant"] : ["en-US"]
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([req])
        }
    }
}

private struct NJOutlinePencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawingPolicy = .anyInput
        view.backgroundColor = UIColor.systemBackground
        view.delegate = context.coordinator
        view.alwaysBounceVertical = false
        view.alwaysBounceHorizontal = false
        view.minimumZoomScale = 1
        view.maximumZoomScale = 1
        view.tool = PKInkingTool(.pen, color: .label, width: 3)
        return view
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: NJOutlinePencilCanvas
        init(_ parent: NJOutlinePencilCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

#if os(iOS)
private struct NJKeyboardControlledTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var keyboardVisible: Bool
    @Binding var isFirstResponder: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFirstResponder: $isFirstResponder)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField(frame: .zero)
        tf.borderStyle = .none
        tf.placeholder = placeholder
        tf.text = text
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.smartInsertDeleteType = .no
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder

        // Hide software keyboard while still allowing text field focus/cursor.
        uiView.inputView = keyboardVisible ? nil : UIView(frame: .zero)
        uiView.reloadInputViews()

        if isFirstResponder && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var isFirstResponder: Bool

        init(text: Binding<String>, isFirstResponder: Binding<Bool>) {
            _text = text
            _isFirstResponder = isFirstResponder
        }

        @objc func textChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFirstResponder = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFirstResponder = false
        }
    }
}
#endif
#endif

struct NJOutlineNodeDetailWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @ObservedObject var outline: NJOutlineStore

    let nodeID: String

    @StateObject private var persistence = NJReconstructedNotePersistence(spec: .all(limit: 1))

    @State private var titleDraft: String = ""
    @State private var commentDraft: String = ""
    @State private var domainDraft: String = ""

    @State private var metaExpanded = true
    @State private var commentDomainExpanded = false
    @State private var scheduleExpanded = true
    @State private var filterExpanded = false

    @State private var filterOp: String = "AND"
    @State private var rules: [NJOutlineFilterRule] = []
    @State private var fromEnabled = false
    @State private var toEnabled = false
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var nodeStartEnabled = false
    @State private var nodeEndEnabled = false
    @State private var nodeStartDate = Date()
    @State private var nodeEndDate = Date()
    @State private var nodeProgressPct: Double = 0

    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    @State private var focusedHandle: NJProtonEditorHandle? = nil
    @State private var showClipboardAttach = false
    @State private var attachedBlockRefs: [NJOutlineBlockRef] = []

    private var node: NJOutlineNodeRecord? { outline.node(nodeID) }
    private var hasAnyFilter: Bool {
        let hasRules = rules.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasRules
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if node != nil {
                    metadataSection()
                    Divider()
                    filterSection()
                    Divider()
                    reconstructedList()
                } else {
                    ContentUnavailableView("Node not found", systemImage: "exclamationmark.triangle")
                }
            }
            .font(.system(size: 12))
            .navigationTitle(titleDraft.isEmpty ? "Node" : titleDraft)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let h = focusedHandle ?? persistence.blocks.first(where: { $0.id == persistence.focusedBlockID })?.protonHandle {
                    NJProtonFloatingFormatBar(
                        handle: h,
                        pickedPhotoItem: $pickedPhotoItem,
                        currentHandle: { focusedHandle ?? persistence.blocks.first(where: { $0.id == persistence.focusedBlockID })?.protonHandle }
                    )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addBlankBlock()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showClipboardAttach = true
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { saveAll() } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .onAppear {
                persistence.configure(store: store)
                syncDrafts()
                loadFilterFromNode()
                loadAttachedBlockRefs()
                refreshReconstructed()
            }
            .onChange(of: nodeStartEnabled) { _, _ in normalizeNodeScheduleDateRange() }
            .onChange(of: nodeStartDate) { _, _ in normalizeNodeScheduleDateRange() }
            .onChange(of: nodeEndEnabled) { _, _ in normalizeNodeScheduleDateRange() }
            .onChange(of: nodeEndDate) { _, _ in normalizeNodeScheduleDateRange() }
            .onChange(of: fromEnabled) { _, _ in normalizeFilterDateRange() }
            .onChange(of: fromDate) { _, _ in normalizeFilterDateRange() }
            .onChange(of: toEnabled) { _, _ in normalizeFilterDateRange() }
            .onChange(of: toDate) { _, _ in normalizeFilterDateRange() }
            .onDisappear {
                if let id = persistence.focusedBlockID {
                    persistence.forceEndEditingAndCommitNow(id)
                }
            }
            .sheet(isPresented: $showClipboardAttach) {
                NavigationStack {
                    NJOutlineClipboardAttachSheet(nodeID: nodeID) { blockID, extraDomain in
                        attachBlockRef(blockID: blockID, extraDomain: extraDomain)
                    }
                    .environmentObject(store)
                }
            }
        }
    }

    private func metadataSection() -> some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    metaExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: metaExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Node")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if metaExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)

                    VStack(spacing: 6) {
                        HStack {
                            Button {
                                commentDomainExpanded.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: commentDomainExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Comment & Domain")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        if commentDomainExpanded {
                            TextField("Domain", text: $domainDraft)
                                .textFieldStyle(.roundedBorder)
                            TextEditor(text: $commentDraft)
                                .font(.system(size: 12))
                                .frame(minHeight: 80)
                                .padding(6)
                                .background(Color(UIColor.secondarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(UIColor.separator), lineWidth: 0.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    VStack(spacing: 6) {
                        HStack {
                            Button {
                                scheduleExpanded.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: scheduleExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Schedule")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        if scheduleExpanded {
                            HStack(spacing: 10) {
                                Text("Progress")
                                    .font(.system(size: 12, weight: .semibold))
                                Slider(value: $nodeProgressPct, in: 0...100, step: 1)
                                Text("\(Int(nodeProgressPct))%")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .font(.system(size: 12))

                            HStack(spacing: 10) {
                                Toggle("Start", isOn: $nodeStartEnabled)
                                if nodeStartEnabled {
                                    DatePicker("", selection: $nodeStartDate, displayedComponents: .date)
                                        .font(.system(size: 12))
                                        .labelsHidden()
                                }
                                Spacer()
                            }
                            .font(.system(size: 12))

                            HStack(spacing: 10) {
                                Toggle("End", isOn: $nodeEndEnabled)
                                if nodeEndEnabled {
                                    DatePicker("", selection: $nodeEndDate, displayedComponents: .date)
                                        .font(.system(size: 12))
                                        .labelsHidden()
                                }
                                Spacer()
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func filterSection() -> some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    filterExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: filterExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Filters")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    rules.append(NJOutlineFilterRule(field: .domain, value: ""))
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)

                Button {
                    refreshReconstructed()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if filterExpanded {
                VStack(spacing: 8) {
                    Picker("Logic", selection: $filterOp) {
                        Text("AND").tag("AND")
                        Text("OR").tag("OR")
                    }
                    .pickerStyle(.segmented)

                    ForEach(Array(rules.enumerated()), id: \.element.id) { idx, _ in
                        HStack(spacing: 8) {
                            Picker(
                                "Field",
                                selection: Binding(
                                    get: { rules[idx].field },
                                    set: { rules[idx].field = $0 }
                                )
                            ) {
                                ForEach(NJOutlineFilterRule.Field.allCases, id: \.self) { field in
                                    Text(field.label).tag(field)
                                }
                            }
                            .frame(width: 110)

                            TextField(
                                rules[idx].field == .domain ? "Domain contains" : "Tag contains",
                                text: Binding(
                                    get: { rules[idx].value },
                                    set: { rules[idx].value = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            Button {
                                rules.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 10) {
                        Toggle("From", isOn: $fromEnabled)
                            .font(.system(size: 12))
                        if fromEnabled {
                            DatePicker("", selection: $fromDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }

                    HStack(spacing: 10) {
                        Toggle("To", isOn: $toEnabled)
                            .font(.system(size: 12))
                        if toEnabled {
                            DatePicker("", selection: $toDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func reconstructedList() -> some View {
        List {
            if attachedBlockRefs.isEmpty && !hasAnyFilter {
                Text("Add a block or at least one filter to load results")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else if persistence.blocks.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(persistence.blocks, id: \.id) { b in
                    reconstructedRow(b)
                }
            }
        }
        .listStyle(.plain)
    }

    private func reconstructedRow(_ b: NJNoteEditorContainerPersistence.BlockState) -> some View {
        let id = b.id
        let h = b.protonHandle
        let liveTagJSON: String? = persistence.blocks.first(where: { $0.id == id })?.tagJSON

        let onSaveTags: (String) -> Void = { newJSON in
            if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                var arr = persistence.blocks
                arr[i].tagJSON = newJSON
                persistence.blocks = arr
            }
            persistence.markDirty(id)
            persistence.scheduleCommit(id)
        }

        return NJBlockHostView(
            index: 1,
            createdAtMs: b.createdAtMs,
            domainPreview: b.domainPreview,
            onEditTags: { },
            goalPreview: b.goalPreview,
            onAddGoal: { },
            hasClipPDF: false,
            onOpenClipPDF: { },
            protonHandle: h,
            isCollapsed: bindingCollapsed(id),
            isFocused: id == persistence.focusedBlockID,
            attr: Binding(
                get: { persistence.blocks.first(where: { $0.id == id })?.attr ?? NSAttributedString(string: "\u{200B}") },
                set: { v in
                    if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                        var arr = persistence.blocks
                        if persistence.focusedBlockID != arr[i].id { persistence.focusedBlockID = arr[i].id }
                        arr[i].attr = v
                        persistence.blocks = arr
                        persistence.markDirty(id)
                        persistence.scheduleCommit(id)
                    }
                }
            ),
            sel: Binding(
                get: { persistence.blocks.first(where: { $0.id == id })?.sel ?? NSRange(location: 0, length: 0) },
                set: { v in
                    if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                        var arr = persistence.blocks
                        arr[i].sel = v
                        persistence.blocks = arr
                    }
                }
            ),
            onFocus: {
                let prev = persistence.focusedBlockID
                if let prev, prev != id { persistence.forceEndEditingAndCommitNow(prev) }
                persistence.focusedBlockID = id
                persistence.hydrateProton(id)
                focusedHandle = h
                h.focus()
            },
            onCtrlReturn: { persistence.forceEndEditingAndCommitNow(id) },
            onDelete: { },
            onHydrateProton: { persistence.hydrateProton(id) },
            onCommitProton: {
                persistence.markDirty(id)
                persistence.scheduleCommit(id)
            },
            onMoveToClipboard: nil,
            inheritedTags: [],
            editableTags: [],
            tagJSON: liveTagJSON,
            onSaveTagJSON: onSaveTags,
            tagSuggestionsProvider: { prefix, limit in
                store.notes.listTagSuggestions(prefix: prefix, limit: limit)
            }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        .listRowBackground(reconstructedBackground(blockID: b.blockID))
        .listRowSeparator(.hidden)
        .onAppear { persistence.hydrateProton(id) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if attachedBlockRefs.contains(where: { $0.blockID == b.blockID }) {
                Button(role: .destructive) {
                    detachBlockRef(blockID: b.blockID)
                } label: {
                    Image(systemName: "link.badge.minus")
                }
            }
        }
    }

    private func reconstructedBackground(blockID: String) -> Color {
        if let domainColor = persistence.rowBackgroundColor(blockID: blockID) {
            return domainColor
        }
        return Color(red: 0.90, green: 0.95, blue: 1.0)
    }

    private func bindingCollapsed(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.isCollapsed ?? false },
            set: { persistence.setCollapsed(id: id, collapsed: $0) }
        )
    }

    private func refreshReconstructed() {
        let cleanRules = rules.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let effectiveFromMs = cleanRules.isEmpty ? nil : (fromEnabled ? startOfDayMs(fromDate) : nil)
        let effectiveToMs = cleanRules.isEmpty ? nil : (toEnabled ? endOfDayMs(toDate) : nil)
        let attachedIDs = attachedBlockRefs.map(\.blockID)

        if cleanRules.isEmpty && attachedIDs.isEmpty {
            persistence.updateSpec(.custom(title: titleDraft.isEmpty ? "Node" : titleDraft, ids: [], limit: 1, newestFirst: true))
            persistence.reload(makeHandle: { NJProtonEditorHandle() })
            return
        }

        let filteredIDs = cleanRules.isEmpty ? [] : outline.reconstructedBlockIDs(
            rules: cleanRules,
            op: filterOp,
            startMs: effectiveFromMs,
            endMs: effectiveToMs,
            limit: 300
        )
        let ids = Array(NSOrderedSet(array: attachedIDs + filteredIDs)) as? [String] ?? (attachedIDs + filteredIDs)
        persistence.updateSpec(.custom(title: titleDraft.isEmpty ? "Node" : titleDraft, ids: ids, limit: max(ids.count, 1), newestFirst: true))
        persistence.reload(makeHandle: { NJProtonEditorHandle() })
    }

    private func saveAll() {
        normalizeNodeScheduleDateRange()
        outline.updateNodeTitle(nodeID: nodeID, title: titleDraft)
        outline.updateNodeDomain(nodeID: nodeID, domainTag: domainDraft)
        outline.updateNodeComment(nodeID: nodeID, comment: commentDraft)
        var filter = makeFilterObject()
        if nodeStartEnabled {
            filter["start_ms"] = startOfDayMs(nodeStartDate)
        } else {
            filter.removeValue(forKey: "start_ms")
        }
        if nodeEndEnabled {
            filter["end_ms"] = endOfDayMs(nodeEndDate)
        } else {
            filter.removeValue(forKey: "end_ms")
        }
        let pct = Int64(max(0, min(100, Int(nodeProgressPct.rounded()))))
        filter["progress_pct"] = pct
        outline.setNodeFilter(nodeID: nodeID, filter: filter)
        if let n = node, n.isChecklist {
            if pct >= 100, !n.isChecked {
                outline.toggleChecked(nodeID: nodeID)
            } else if pct < 100, n.isChecked {
                outline.toggleChecked(nodeID: nodeID)
            }
        }
        dismiss()
    }

    private func syncDrafts() {
        guard let n = node else { return }
        titleDraft = n.title
        commentDraft = n.comment
        domainDraft = n.domainTag

        let f = outline.nodeFilter(nodeID: nodeID)
        if let start = asInt64(f["start_ms"]) {
            nodeStartEnabled = true
            nodeStartDate = Date(timeIntervalSince1970: TimeInterval(start) / 1000.0)
        } else {
            nodeStartEnabled = false
        }
        if let end = asInt64(f["end_ms"]) {
            nodeEndEnabled = true
            nodeEndDate = Date(timeIntervalSince1970: TimeInterval(end) / 1000.0)
        } else {
            nodeEndEnabled = false
        }
        if let pct = asInt64(f["progress_pct"]) {
            nodeProgressPct = max(0, min(100, Double(pct)))
        } else if n.isChecklist {
            nodeProgressPct = n.isChecked ? 100 : 0
        } else {
            nodeProgressPct = 0
        }
    }

    private func loadAttachedBlockRefs() {
        attachedBlockRefs = outline.blockRefs(nodeID: nodeID)
    }

    private func attachBlockRef(blockID: String, extraDomain: String, refresh: Bool = true) {
        let cleanedBlockID = blockID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBlockID.isEmpty else { return }
        var refs = attachedBlockRefs.filter { $0.blockID != cleanedBlockID }
        refs.insert(NJOutlineBlockRef(blockID: cleanedBlockID, extraDomain: extraDomain.trimmingCharacters(in: .whitespacesAndNewlines)), at: 0)
        outline.setBlockRefs(nodeID: nodeID, refs: refs)
        loadAttachedBlockRefs()
        if refresh {
            refreshReconstructed()
        } else {
            updateReconstructedSpecOnly()
        }
    }

    private func detachBlockRef(blockID: String) {
        outline.setBlockRefs(nodeID: nodeID, refs: attachedBlockRefs.filter { $0.blockID != blockID })
        loadAttachedBlockRefs()
        refreshReconstructed()
    }

    private func addBlankBlock() {
        let blockID = UUID().uuidString
        let bootstrapHandle = NJProtonEditorHandle()
        let bootstrapProtonJSON = bootstrapHandle.exportProtonJSONString(from: NSAttributedString(string: "\u{200B}"))
        store.notes.saveSingleProtonBlock(
            blockID: blockID,
            protonJSON: bootstrapProtonJSON,
            tagJSON: ""
        )
        attachBlockRef(blockID: blockID, extraDomain: "", refresh: true)
        store.sync.schedulePush(debounceMs: 0)
    }

    private func updateReconstructedSpecOnly() {
        let cleanRules = rules.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let effectiveFromMs = cleanRules.isEmpty ? nil : (fromEnabled ? startOfDayMs(fromDate) : nil)
        let effectiveToMs = cleanRules.isEmpty ? nil : (toEnabled ? endOfDayMs(toDate) : nil)
        let attachedIDs = attachedBlockRefs.map(\.blockID)
        let filteredIDs = cleanRules.isEmpty ? [] : outline.reconstructedBlockIDs(
            rules: cleanRules,
            op: filterOp,
            startMs: effectiveFromMs,
            endMs: effectiveToMs,
            limit: 300
        )
        let ids = Array(NSOrderedSet(array: attachedIDs + filteredIDs)) as? [String] ?? (attachedIDs + filteredIDs)
        persistence.updateSpec(.custom(title: titleDraft.isEmpty ? "Node" : titleDraft, ids: ids, limit: max(ids.count, 1), newestFirst: true))
    }

    private func loadFilterFromNode() {
        let f = outline.nodeFilter(nodeID: nodeID)
        filterOp = ((f["op"] as? String) ?? "AND").uppercased() == "OR" ? "OR" : "AND"

        if let arr = f["rules"] as? [[String: Any]] {
            let parsed = arr.compactMap { obj -> NJOutlineFilterRule? in
                guard let fieldRaw = obj["field"] as? String,
                      let field = NJOutlineFilterRule.Field(rawValue: fieldRaw),
                      let value = obj["value"] as? String else { return nil }
                return NJOutlineFilterRule(field: field, value: value)
            }
            rules = parsed
        } else {
            rules = []
            let legacyDomain = (f["domain"] as? String) ?? ""
            let legacyTagsCSV = (f["tags"] as? String) ?? ""
            if !legacyDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rules.append(NJOutlineFilterRule(field: .domain, value: legacyDomain))
            }
            let tags = legacyTagsCSV
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for t in tags {
                rules.append(NJOutlineFilterRule(field: .tag, value: t))
            }
        }

        if let from = asInt64(f["start_ms"]) {
            fromEnabled = true
            fromDate = Date(timeIntervalSince1970: TimeInterval(from) / 1000.0)
        } else {
            fromEnabled = false
        }
        if let to = asInt64(f["end_ms"]) {
            toEnabled = true
            toDate = Date(timeIntervalSince1970: TimeInterval(to) / 1000.0)
        } else {
            toEnabled = false
        }
    }

    private func makeFilterObject() -> [String: Any] {
        var out: [String: Any] = [
            "op": filterOp,
            "rules": rules.map { ["field": $0.field.rawValue, "value": $0.value] }
        ]
        if fromEnabled {
            out["start_ms"] = startOfDayMs(fromDate)
        }
        if toEnabled {
            out["end_ms"] = endOfDayMs(toDate)
        }
        return out
    }

    private func startOfDayMs(_ d: Date) -> Int64 {
        let day = Calendar.current.startOfDay(for: d)
        return Int64(day.timeIntervalSince1970 * 1000.0)
    }

    private func endOfDayMs(_ d: Date) -> Int64 {
        let start = Calendar.current.startOfDay(for: d)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? d
        return Int64(next.timeIntervalSince1970 * 1000.0) - 1
    }

    private func normalizeNodeScheduleDateRange() {
        guard nodeStartEnabled else { return }
        if nodeEndEnabled && nodeEndDate < nodeStartDate {
            nodeEndDate = nodeStartDate
        }
    }

    private func normalizeFilterDateRange() {
        guard fromEnabled else { return }
        if toEnabled && toDate < fromDate {
            toDate = fromDate
        }
    }

    private func asInt64(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? Double { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }
}

private struct NJOutlineClipboardAttachSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let nodeID: String
    let onAttach: (String, String) -> Void

    @State private var rows: [Row] = []
    @State private var selectedBlockID: String? = nil
    @State private var extraDomainDraft: String = ""

    struct Row: Identifiable, Equatable {
        enum Kind: String {
            case clip
            case audio
            case quick
        }
        let id: String
        let createdAtMs: Int64
        let title: String
        let kind: Kind
    }

    private var selectedRow: Row? {
        guard let selectedBlockID else { return nil }
        return rows.first(where: { $0.id == selectedBlockID })
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    TextField("Additional Domain (Optional)", text: $extraDomainDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                Section {
                    ForEach(rows) { row in
                        Button {
                            selectedBlockID = row.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(njDate(row.createdAtMs))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(row.kind.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(row.title.isEmpty ? "(untitled)" : row.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedBlockID == row.id ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                } header: {
                    Text("Clipboard Blocks")
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Button("Refresh") { reload() }
                Spacer()
                Button("Attach") {
                    guard let selected = selectedRow else { return }
                    onAttach(selected.id, extraDomainDraft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRow == nil)
            }
            .padding(12)
        }
        .navigationTitle("Attach Block")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        let clips = store.notes.listOrphanClipBlocks(limit: 500).map {
            Row(id: $0.id, createdAtMs: $0.createdAtMs, title: parsePayloadTitle($0.payloadJSON), kind: .clip)
        }
        let audio = store.notes.listOrphanAudioBlocks(limit: 500).map {
            Row(id: $0.id, createdAtMs: $0.createdAtMs, title: parsePayloadTitle($0.payloadJSON), kind: .audio)
        }
        let quick = store.notes.listOrphanQuickBlocks(limit: 500).map {
            Row(id: $0.id, createdAtMs: $0.createdAtMs, title: parsePayloadTitle($0.payloadJSON), kind: .quick)
        }
        rows = (clips + audio + quick).sorted { $0.createdAtMs > $1.createdAtMs }
    }

    private func parsePayloadTitle(_ payload: String) -> String {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let title = obj["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        if let sections = obj["sections"] as? [String: Any] {
            for key in ["clip", "audio", "quick"] {
                if let section = sections[key] as? [String: Any],
                   let data = section["data"] as? [String: Any],
                   let title = data["title"] as? String,
                   !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return title
                }
            }
        }
        return ""
    }

    private func njDate(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMM d, HH:mm")
        return f.string(from: d)
    }
}
