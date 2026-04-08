import SwiftUI
import Combine

private enum NJWatchTimeSlotCategory: String, Codable {
    case personal = "Personal"
}

private struct NJWatchTimeSlot: Identifiable, Codable {
    let id: String
    var title: String
    var category: NJWatchTimeSlotCategory
    var startDate: Date
    var endDate: Date
    var notes: String
}

private struct NJWatchActiveTracker: Codable {
    var title: String
    var startDate: Date
    var notes: String
}

private struct NJWatchTrackerPreset: Identifiable {
    let id: String
    let title: String
    let icon: String

    init(title: String, icon: String) {
        self.id = title
        self.title = title
        self.icon = icon
    }
}

private struct NJWatchMusicInstrument: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let songs: [NJWatchMusicSong]

    init(name: String, icon: String, songs: [NJWatchMusicSong]) {
        self.id = name
        self.name = name
        self.icon = icon
        self.songs = songs
    }
}

private struct NJWatchMusicSong: Identifiable, Hashable {
    let id: String
    let title: String

    init(title: String) {
        self.id = title
        self.title = title
    }
}

@MainActor
private final class NJWatchTimeSlotViewModel: ObservableObject {
    @Published private(set) var todaySlots: [NJWatchTimeSlot] = []
    @Published private(set) var activeTracker: NJWatchActiveTracker? = nil
    @Published private(set) var now: Date = Date()

    private let defaults: UserDefaults
    private let slotsKey = "nj_time_module_slots_v1"
    private let trackerKey = "nj_watch_active_tracker_v1"
    private var timerCancellable: AnyCancellable?

    let presets: [NJWatchTrackerPreset] = [
        NJWatchTrackerPreset(title: "Reflection", icon: "book.closed"),
        NJWatchTrackerPreset(title: "MM Play Time", icon: "figure.play"),
        NJWatchTrackerPreset(title: "MM Story time", icon: "text.book.closed"),
    ]

    let musicInstruments: [NJWatchMusicInstrument] = [
        NJWatchMusicInstrument(
            name: "Piano",
            icon: "pianokeys",
            songs: [
                NJWatchMusicSong(title: "Midnight Rhapsody"),
                NJWatchMusicSong(title: "Canon in D"),
                NJWatchMusicSong(title: "Lemon Sky"),
                NJWatchMusicSong(title: "General Practice"),
            ]
        ),
        NJWatchMusicInstrument(
            name: "Ukulele",
            icon: "guitars",
            songs: [
                NJWatchMusicSong(title: "天空之城"),
                NJWatchMusicSong(title: "General Practice"),
            ]
        ),
    ]

    init() {
        defaults = UserDefaults(suiteName: "group.com.CYC.NotionJournal") ?? .standard
        reload()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.now = date
            }
    }

    func reload() {
        if let data = defaults.data(forKey: trackerKey),
           let decoded = try? JSONDecoder().decode(NJWatchActiveTracker.self, from: data) {
            activeTracker = decoded
        } else {
            activeTracker = nil
        }

        guard let data = defaults.data(forKey: slotsKey),
              let decoded = try? JSONDecoder().decode([NJWatchTimeSlot].self, from: data) else {
            todaySlots = []
            return
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        todaySlots = decoded
            .filter { $0.startDate >= start && $0.startDate < end }
            .sorted { $0.startDate > $1.startDate }
    }

    func startTracker(title: String) {
        let tracker = NJWatchActiveTracker(
            title: title,
            startDate: Date(),
            notes: "From Watch Tracker"
        )
        guard let data = try? JSONEncoder().encode(tracker) else { return }
        defaults.set(data, forKey: trackerKey)
        activeTracker = tracker
    }

    func endTracker() {
        guard let tracker = activeTracker else { return }

        var slots: [NJWatchTimeSlot] = []
        if let data = defaults.data(forKey: slotsKey),
           let decoded = try? JSONDecoder().decode([NJWatchTimeSlot].self, from: data) {
            slots = decoded
        }

        slots.append(
            NJWatchTimeSlot(
                id: UUID().uuidString.lowercased(),
                title: tracker.title,
                category: .personal,
                startDate: tracker.startDate,
                endDate: max(Date(), tracker.startDate.addingTimeInterval(60)),
                notes: tracker.notes
            )
        )

        guard let data = try? JSONEncoder().encode(slots) else { return }
        defaults.set(data, forKey: slotsKey)
        defaults.removeObject(forKey: trackerKey)
        activeTracker = nil
        reload()
    }

    func musicSongs(for instrument: NJWatchMusicInstrument) -> [NJWatchMusicSong] {
        instrument.songs
    }

    func startMusicTracker(instrument: NJWatchMusicInstrument, song: NJWatchMusicSong) {
        startTracker(title: "Music - \(instrument.name) - \(song.title)")
    }
}

struct NotionJournalWatchHomeView: View {
    @StateObject private var viewModel = NJWatchTimeSlotViewModel()

    var body: some View {
        List {
            if let tracker = viewModel.activeTracker {
                Section("Tracking") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tracker.title)
                            .font(.headline)
                        Text(elapsedText(since: tracker.startDate, now: viewModel.now))
                            .font(.title3.monospacedDigit())
                        Text(startedText(tracker.startDate))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("End Tracker") {
                            viewModel.endTracker()
                        }
                        .tint(.red)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section("Start Tracker") {
                    NavigationLink {
                        NJWatchMusicInstrumentView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Label("Music", systemImage: "music.note")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(viewModel.presets) { preset in
                        Button {
                            viewModel.startTracker(title: preset.title)
                        } label: {
                            HStack {
                                Label(preset.title, systemImage: preset.icon)
                                Spacer()
                                Image(systemName: "play.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Today") {
                if viewModel.todaySlots.isEmpty {
                    Text("No time slots yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.todaySlots.prefix(6))) { slot in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                Text(slot.title)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            Text(timeRange(slot))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Time")
        .onAppear { viewModel.reload() }
    }

    private func timeRange(_ slot: NJWatchTimeSlot) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: slot.startDate)) - \(formatter.string(from: slot.endDate))"
    }

    private func startedText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Started \(formatter.string(from: date))"
    }

    private func elapsedText(since start: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct NJWatchMusicInstrumentView: View {
    @ObservedObject var viewModel: NJWatchTimeSlotViewModel

    var body: some View {
        List {
            ForEach(viewModel.musicInstruments) { instrument in
                NavigationLink {
                    NJWatchMusicSongView(viewModel: viewModel, instrument: instrument)
                } label: {
                    Label(instrument.name, systemImage: instrument.icon)
                }
            }
        }
        .navigationTitle("Instrument")
    }
}

private struct NJWatchMusicSongView: View {
    @ObservedObject var viewModel: NJWatchTimeSlotViewModel
    let instrument: NJWatchMusicInstrument

    var body: some View {
        List {
            ForEach(viewModel.musicSongs(for: instrument)) { song in
                Button(song.title) {
                    viewModel.startMusicTracker(instrument: instrument, song: song)
                }
            }
        }
        .navigationTitle("Song")
    }
}
