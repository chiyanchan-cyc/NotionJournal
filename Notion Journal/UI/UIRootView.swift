import SwiftUI
import UIKit
import Combine

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedNoteID: NJNoteID?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @State private var syncTick: Int = 0
    @State private var showProtonListLab: Bool = false

    
    
    var body: some View {
        Group {
            if store.sync.initialPullCompleted {
                NavigationSplitView {
                    Sidebar(selectedNoteID: $selectedNoteID)
                } detail: {
                    switch store.selectedModule {
                    case .note:
                        if let id = selectedNoteID {
                            NJNoteEditorContainerView(noteID: id)
                                .id(String(describing: id))
    //                            .toolbar {
    //                                ToolbarItem(placement: .topBarTrailing) {
    //                                    Button {
    //                                        showProtonListLab = true
    //                                    } label: {
    //                                        Image(systemName: "ladybug")
    //                                    }
    //                                }
    //                            }
                                .sheet(isPresented: $showProtonListLab) {
    //                                NavigationStack {
    //                                    NJProtonListLabView()
    //                                }
                                }
                        } else {
                            ContentUnavailableView("Select a note", systemImage: "doc.text")
                        }
                    case .goal:
                        if let gid = store.selectedGoalID {
                            NJGoalDetailWorkspaceView(goalID: gid)
                                .environmentObject(store)
                        } else {
                            ContentUnavailableView("Select a goal", systemImage: "target")
                        }
                    case .outline:
                        if let id = store.selectedOutlineID {
                            NJOutlineDetailView(outline: store.outline, outlineID: id)
                                .environmentObject(store)
                        } else {
                            ContentUnavailableView("Select an outline", systemImage: "list.bullet.rectangle")
                        }
                    }
                }
                .onAppear {
                    store.runClipIngestIfNeeded()
                    store.runAudioIngestIfNeeded()
                    store.runAudioTranscribeIfNeeded()
                    NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                    NJHealthLogger.shared.configure(db: store.db)
                    NJHealthLogger.shared.appDidBecomeActive()
                }
                .onChange(of: scenePhase) { ph in
                    if ph == .active {
                        store.runClipIngestIfNeeded()
                        store.runAudioIngestIfNeeded()
                        store.runAudioTranscribeIfNeeded()
                        NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                        NJHealthLogger.shared.configure(db: store.db)
                        NJHealthLogger.shared.appDidBecomeActive()
                    }
                }
                .onChange(of: store.selectedNotebookID) { _ in
                    NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                }
                .onChange(of: store.selectedTabID) { _ in
                    NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                }

            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Syncing…")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(store.sync.objectWillChange) { _ in
            syncTick += 1
        }
        .alert("Goals Updated", isPresented: $store.showGoalMigrationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Updated \(store.goalMigrationCount) goal(s) to In Progress based on goal tags.")
        }
    }
}
