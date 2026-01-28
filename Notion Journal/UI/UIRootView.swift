import SwiftUI
import UIKit
import Combine

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedNoteID: NJNoteID?
    @Environment(\.scenePhase) private var scenePhase
    @State private var syncTick: Int = 0
    @State private var showProtonListLab: Bool = false

    
    
    var body: some View {
        Group {
            if store.sync.initialPullCompleted {
                NavigationSplitView {
                    Sidebar(selectedNoteID: $selectedNoteID)
                } detail: {
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
                }
                .onAppear {
                    store.runClipIngestIfNeeded()
                    NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                }
                .onChange(of: scenePhase) { ph in
                    if ph == .active {
                        store.runClipIngestIfNeeded()
                        NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
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
    }
}
