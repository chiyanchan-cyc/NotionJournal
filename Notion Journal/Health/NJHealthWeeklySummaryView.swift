import SwiftUI

struct NJHealthWeeklySummaryView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedDate = Date()
    @State private var includeAI = true
    @State private var isLoading = false
    @State private var errorText = ""

    @State private var rangeSummary: NJHealthSummary.RangeSummary?
    @State private var trendSummary: NJHealthSummary.TrendSummary?
    @State private var daySummaries: [DaySummary] = []
    @State private var weekComparisons: WeekComparisons?

    var body: some View {
        Form {
            Section("Week") {
                DatePicker(
                    "Pick a date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)

                weekStripView

                HStack {
                    Toggle("Use Apple Intelligence", isOn: $includeAI)
                    Spacer()
                    Button("Refresh") { load() }
                }
            }

            Section("Summary") {
                if isLoading {
                    ProgressView("Loading…")
                } else if !errorText.isEmpty {
                    Text(errorText).foregroundStyle(.secondary)
                } else if let rangeSummary {
                    weeklyDashboard

                    Divider()

                    summaryCharts(rangeSummary)

                    Divider()

                    Text(rangeSummary.sourceText)
                        .font(.footnote)
                        .textSelection(.enabled)

                    if let ai = rangeSummary.ai, let summary = ai.summary, !summary.isEmpty {
                        Divider()
                        Text(summary)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("No data")
                        .foregroundStyle(.secondary)
                }
            }

            Section("4-Week Trend") {
                if isLoading {
                    ProgressView("Loading trend…")
                } else if let trendSummary, let weekComparisons {
                    trendCharts(trendSummary)

                    Divider()

                    comparisonCharts(weekComparisons)

                    let comments = trendCommentary(trendSummary)
                    if !comments.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Commentary")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ForEach(comments, id: \.self) { line in
                                Text("• \(line)")
                                    .font(.footnote)
                            }
                        }
                    }

                    Divider()

                    Text(trendSummary.trendText)
                        .font(.footnote)
                        .textSelection(.enabled)

                    if let ai = trendSummary.ai, let summary = ai.summary, !summary.isEmpty {
                        Divider()
                        Text(summary)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("No trend data")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Weekly Health")
        .onAppear { load() }
        .onChange(of: selectedDate) { load() }
        .onChange(of: includeAI) { load() }
    }

    private var weekInterval: DateInterval {
        let cal = Calendar.current
        return cal.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: selectedDate, duration: 7 * 24 * 60 * 60)
    }

    private var weekStripView: some View {
        let cal = Calendar.current
        let start = weekInterval.start

        return HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { idx in
                let day = cal.date(byAdding: .day, value: idx, to: start) ?? start
                let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
                VStack(spacing: 4) {
                    Text(shortWeekday(day))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(cal.component(.day, from: day)))
                        .font(.footnote)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }

    private func shortWeekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    private func load() {
        errorText = ""
        isLoading = true

        let interval = weekInterval

        Task {
            let range = await NJHealthSummary.summarizeRange(
                db: store.db,
                start: interval.start,
                end: interval.end,
                includeAISummary: includeAI
            )

            let cal = Calendar.current
            let trendEnd = interval.end
            let trendStart = cal.date(byAdding: .day, value: -28, to: trendEnd) ?? interval.start
            let trend = await NJHealthSummary.summarizeWeeklyTrend(
                db: store.db,
                start: trendStart,
                end: trendEnd,
                includeAISummary: includeAI
            )

            let days = loadDaySummaries(db: store.db, start: interval.start, end: interval.end)
            let comparisons = loadWeekComparisons(db: store.db, end: interval.end)

            await MainActor.run {
                rangeSummary = range
                trendSummary = trend
                daySummaries = days
                weekComparisons = comparisons
                isLoading = false
            }
        }
    }

    private func summaryCharts(_ summary: NJHealthSummary.RangeSummary) -> some View {
        let sleepHours = Double(summary.sleep.asleepMs) / 1000.0 / 3600.0
        let workoutHours = summary.workouts.totalDurationSec / 3600.0
        let sysAvg = summary.systolic.avg ?? 0
        let weightAvg = summary.weight.avg ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Quick Charts")
                .font(.footnote)
                .foregroundStyle(.secondary)

            MetricBar(label: "Sleep hours", value: sleepHours, unit: "h", target: 56)
            MetricBar(label: "Workout hours", value: workoutHours, unit: "h", target: 5)
            MetricBar(label: "BP systolic avg", value: sysAvg, unit: "mmHg", target: 140)
            if weightAvg > 0 {
                MetricBar(label: "Weight avg", value: weightAvg, unit: "kg", target: max(weightAvg * 1.15, 1))
            }
        }
    }

    private func trendCharts(_ trend: NJHealthSummary.TrendSummary) -> some View {
        let weeks = trend.weeks
        let sleep = weeks.map { Double($0.summary.sleep.asleepMs) / 1000.0 / 3600.0 }
        let workout = weeks.map { $0.summary.workouts.totalDurationSec / 3600.0 }
        let weight = weeks.map { $0.summary.weight.avg ?? 0 }
        let sys = weeks.map { $0.summary.systolic.avg ?? 0 }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Trend Charts")
                .font(.footnote)
                .foregroundStyle(.secondary)

            WeekBarChart(title: "Sleep (hours)", values: sleep, barColor: .blue)
            WeekBarChart(title: "Workouts (hours)", values: workout, barColor: .green)
            WeekBarChart(title: "BP systolic avg", values: sys, barColor: .orange)
            if weight.contains(where: { $0 > 0 }) {
                WeekBarChart(title: "Weight avg", values: weight, barColor: .purple)
            }
        }
    }

    private func trendCommentary(_ trend: NJHealthSummary.TrendSummary) -> [String] {
        let weeks = trend.weeks
        guard weeks.count >= 2 else { return [] }
        let last = weeks[weeks.count - 1]
        let prev = weeks[weeks.count - 2]

        var out: [String] = []

        let lastSleep = Double(last.summary.sleep.asleepMs) / 1000.0 / 3600.0
        let prevSleep = Double(prev.summary.sleep.asleepMs) / 1000.0 / 3600.0
        if let c = deltaComment(name: "Sleep", a: prevSleep, b: lastSleep, unit: "h") { out.append(c) }

        let lastWorkout = last.summary.workouts.totalDurationSec / 3600.0
        let prevWorkout = prev.summary.workouts.totalDurationSec / 3600.0
        if let c = deltaComment(name: "Workout time", a: prevWorkout, b: lastWorkout, unit: "h") { out.append(c) }

        if let wa = prev.summary.weight.avg, let wb = last.summary.weight.avg {
            if let c = deltaComment(name: "Weight avg", a: wa, b: wb, unit: "kg") { out.append(c) }
        }

        if let sa = prev.summary.systolic.avg, let sb = last.summary.systolic.avg {
            if let c = deltaComment(name: "BP systolic avg", a: sa, b: sb, unit: "mmHg") { out.append(c) }
        }

        if let activity = activityIncreaseComment(prev: prev, last: last) {
            out.append(activity)
        }

        return out
    }

    private func deltaComment(name: String, a: Double, b: Double, unit: String) -> String? {
        let delta = b - a
        let absDelta = abs(delta)
        if absDelta < 0.1 { return "\(name) stayed flat" }
        let dir = delta > 0 ? "up" : "down"
        return "\(name) \(dir) \(fmtNum(absDelta)) \(unit)"
    }

    private func activityIncreaseComment(prev: NJHealthSummary.WeekSummary, last: NJHealthSummary.WeekSummary) -> String? {
        let p = prev.summary.workouts.byActivity
        let l = last.summary.workouts.byActivity
        var best: (name: String, delta: Double)?

        for (raw, v) in l {
            let prevDur = p[raw]?.durationSec ?? 0
            let delta = v.durationSec - prevDur
            if delta <= 0 { continue }
            if best == nil || delta > (best?.delta ?? 0) {
                best = (raw, delta)
            }
        }

        guard let best, best.delta >= 30 * 60 else { return nil }
        let name = prettyActivity(best.name)
        return "\(name.capitalized) more: +\(fmtDurSec(best.delta))"
    }

    private func prettyActivity(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "HKWorkoutActivityType.", with: "")
        s = s.replacingOccurrences(of: "_", with: " ")
        return s.lowercased()
    }

    private var weeklyDashboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly Dashboard")
                .font(.footnote)
                .foregroundStyle(.secondary)

            let hasAnyMedData = daySummaries.reduce(into: 0) { $0 += $1.medDoseCount } > 0

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("")
                        .frame(width: 64, alignment: .leading)
                    ForEach(daySummaries, id: \.startMs) { day in
                        VStack(spacing: 2) {
                            Text(dayShort(day.startMs))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(dayNumber(day.startMs))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                GridRow {
                    Text("Meds")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    ForEach(daySummaries, id: \.startMs) { day in
                        MedDoseCell(status: medStatus(day: day, hasAny: hasAnyMedData), count: day.medDoseCount)
                            .frame(maxWidth: .infinity)
                    }
                }

                GridRow {
                    Text("Sleep")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    ForEach(daySummaries, id: \.startMs) { day in
                        Text("\(fmtNum(day.sleepHours))h")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                }

                GridRow {
                    Text("Workout")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    ForEach(daySummaries, id: \.startMs) { day in
                        Text("\(fmtNum(day.workoutHours))h")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                }

                GridRow {
                    Text("BP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    ForEach(daySummaries, id: \.startMs) { day in
                        Text(bpText(day))
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if !hasAnyMedData {
                Text("No medication dose data found for this week.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dayLabel(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d"
        return f.string(from: d)
    }

    private func dayShort(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    private func dayNumber(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d"
        return f.string(from: d)
    }

    private func medStatus(day: DaySummary, hasAny: Bool) -> MedDot.Status {
        if !hasAny { return .unknown }
        return day.medDoseCount > 0 ? .taken : .missed
    }

    private func loadDaySummaries(db: SQLiteDB, start: Date, end: Date) -> [DaySummary] {
        var out: [DaySummary] = []
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: start)

        while cursor < end {
            let next = cal.date(byAdding: .day, value: 1, to: cursor) ?? end
            let startMs = Int64(cursor.timeIntervalSince1970 * 1000.0)
            let endMs = Int64(next.timeIntervalSince1970 * 1000.0)

            let sleepHours = sumSleepHours(db: db, startMs: startMs, endMs: endMs)
            let workoutHours = sumWorkoutHours(db: db, startMs: startMs, endMs: endMs)
            let medDoseCount = countMeds(db: db, startMs: startMs, endMs: endMs)
            let sysAvg = avgValue(db: db, type: "blood_pressure_systolic", startMs: startMs, endMs: endMs)
            let diaAvg = avgValue(db: db, type: "blood_pressure_diastolic", startMs: startMs, endMs: endMs)

            out.append(DaySummary(
                startMs: startMs,
                sleepHours: sleepHours,
                workoutHours: workoutHours,
                medDoseCount: medDoseCount,
                systolicAvg: sysAvg,
                diastolicAvg: diaAvg
            ))
            cursor = next
        }

        return out
    }

    private func sumSleepHours(db: SQLiteDB, startMs: Int64, endMs: Int64) -> Double {
        let sql = """
        SELECT start_ms, end_ms, value_str
        FROM health_samples
        WHERE type = 'sleep'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs);
        """
        let rows = db.queryRows(sql)
        var asleep: Int64 = 0
        for r in rows {
            let s = Int64(r["start_ms"] ?? "") ?? 0
            let e = Int64(r["end_ms"] ?? "") ?? 0
            let value = r["value_str"] ?? ""
            if value == "asleep" {
                asleep += max(0, e - s)
            }
        }
        return Double(asleep) / 1000.0 / 3600.0
    }

    private func sumWorkoutHours(db: SQLiteDB, startMs: Int64, endMs: Int64) -> Double {
        let sql = """
        SELECT value_num
        FROM health_samples
        WHERE type = 'workout'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs);
        """
        let rows = db.queryRows(sql)
        var sec: Double = 0
        for r in rows {
            sec += Double(r["value_num"] ?? "") ?? 0
        }
        return sec / 3600.0
    }

    private func countMeds(db: SQLiteDB, startMs: Int64, endMs: Int64) -> Int {
        let doseSql = """
        SELECT COUNT(*) AS c
        FROM health_samples
        WHERE type = 'medication_dose'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs);
        """
        let doseRows = db.queryRows(doseSql)
        let doseCount = Int(doseRows.first?["c"] ?? "0") ?? 0
        if doseCount > 0 { return doseCount }

        let sql = """
        SELECT COUNT(*) AS c
        FROM health_samples
        WHERE type = 'medication_record'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs);
        """
        let rows = db.queryRows(sql)
        return Int(rows.first?["c"] ?? "0") ?? 0
    }

    private func loadWeekComparisons(db: SQLiteDB, end: Date) -> WeekComparisons? {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -28, to: end) else { return nil }
        let weeks = splitWeeks(start: start, end: end)
        if weeks.count < 2 { return nil }

        var sleep: [Double] = []
        var workout: [Double] = []
        var weight: [Double] = []
        var sys: [Double] = []

        for w in weeks {
            let startMs = Int64(w.start.timeIntervalSince1970 * 1000.0)
            let endMs = Int64(w.end.timeIntervalSince1970 * 1000.0)

            let sleepHours = sumSleepHours(db: db, startMs: startMs, endMs: endMs)
            let workoutHours = sumWorkoutHours(db: db, startMs: startMs, endMs: endMs)
            let weightAvg = avgValue(db: db, type: "weight", startMs: startMs, endMs: endMs)
            let sysAvg = avgValue(db: db, type: "blood_pressure_systolic", startMs: startMs, endMs: endMs)

            sleep.append(sleepHours)
            workout.append(workoutHours)
            weight.append(weightAvg ?? 0)
            sys.append(sysAvg ?? 0)
        }

        let labels = weeks.map { weekLabel($0.start) }
        return WeekComparisons(labels: labels, sleepHours: sleep, workoutHours: workout, weightAvg: weight, sysAvg: sys)
    }

    private func avgValue(db: SQLiteDB, type: String, startMs: Int64, endMs: Int64) -> Double? {
        let sql = """
        SELECT AVG(value_num) AS v
        FROM health_samples
        WHERE type = '\(type)'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs);
        """
        let rows = db.queryRows(sql)
        return Double(rows.first?["v"] ?? "")
    }

    private func splitWeeks(start: Date, end: Date) -> [(start: Date, end: Date)] {
        var out: [(Date, Date)] = []
        let cal = Calendar.current
        var cursor = start

        while cursor < end {
            if let interval = cal.dateInterval(of: .weekOfYear, for: cursor) {
                let wStart = max(interval.start, start)
                let wEnd = min(interval.end, end)
                if wStart < wEnd { out.append((wStart, wEnd)) }
                cursor = interval.end
            } else {
                let next = cal.date(byAdding: .day, value: 7, to: cursor) ?? end
                out.append((cursor, min(next, end)))
                cursor = next
            }
        }

        return out
    }

    private func weekLabel(_ start: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: start)
    }

    private func comparisonCharts(_ comp: WeekComparisons) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week vs Last 3 Weeks")
                .font(.footnote)
                .foregroundStyle(.secondary)

            WeekComparisonRow(title: "Sleep (hours)", labels: comp.labels, values: comp.sleepHours, color: .blue)
            WeekComparisonRow(title: "Workouts (hours)", labels: comp.labels, values: comp.workoutHours, color: .green)
            WeekComparisonRow(title: "BP systolic avg", labels: comp.labels, values: comp.sysAvg, color: .orange)
            if comp.weightAvg.contains(where: { $0 > 0 }) {
                WeekComparisonRow(title: "Weight avg", labels: comp.labels, values: comp.weightAvg, color: .purple)
            }
        }
    }

    private func bpText(_ day: DaySummary) -> String {
        guard let sys = day.systolicAvg, let dia = day.diastolicAvg else { return "-" }
        return "\(fmtNum(sys))/\(fmtNum(dia))"
    }
}

private struct DaySummary {
    let startMs: Int64
    let sleepHours: Double
    let workoutHours: Double
    let medDoseCount: Int
    let systolicAvg: Double?
    let diastolicAvg: Double?
}

private struct WeekComparisons {
    let labels: [String]
    let sleepHours: [Double]
    let workoutHours: [Double]
    let weightAvg: [Double]
    let sysAvg: [Double]
}

private func fmtNum(_ v: Double) -> String {
    let f = NumberFormatter()
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = 1
    return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
}

private func fmtDurSec(_ sec: Double) -> String {
    if sec <= 0 { return "0m" }
    let totalMin = Int(sec / 60.0)
    let h = totalMin / 60
    let m = totalMin % 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

private struct MetricBar: View {
    let label: String
    let value: Double
    let unit: String
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(fmtNum(value)) \(unit)")
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let pct = target <= 0 ? 0 : min(max(value / target, 0), 1)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: w * pct, height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private func fmtNum(_ v: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }
}

private struct WeekBarChart: View {
    let title: String
    let values: [Double]
    let barColor: Color

    var body: some View {
        let maxV = max(values.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(values.indices, id: \.self) { idx in
                    let v = values[idx]
                    let h = CGFloat(v / maxV)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.8))
                        .frame(width: 12, height: max(6, 60 * h))
                }
            }
        }
    }
}

private struct MedDot: View {
    enum Status {
        case taken
        case missed
        case unknown
    }

    let status: Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private var color: Color {
        switch status {
        case .taken: return .green
        case .missed: return .red
        case .unknown: return .gray
        }
    }
}

private struct WeekComparisonRow: View {
    let title: String
    let labels: [String]
    let values: [Double]
    let color: Color

    var body: some View {
        let maxV = max(values.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(values.indices, id: \.self) { idx in
                    let v = values[idx]
                    let h = CGFloat(v / maxV)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(idx == values.count - 1 ? 0.95 : 0.55))
                            .frame(width: 16, height: max(6, 60 * h))
                        Text(shortLabel(labels, idx))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func shortLabel(_ labels: [String], _ idx: Int) -> String {
        guard idx < labels.count else { return "" }
        let s = labels[idx]
        let parts = s.split(separator: " ")
        return parts.last.map(String.init) ?? s
    }
}

private struct MedDoseCell: View {
    let status: MedDot.Status
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            MedDot(status: status)
            Text(countText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var countText: String {
        switch status {
        case .unknown: return "-"
        case .missed: return "0"
        case .taken: return String(count)
        }
    }
}
