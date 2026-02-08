import Foundation

enum NJHealthSummary {
    struct RangeSummary {
        let startMs: Int64
        let endMs: Int64

        let systolic: NumericStats
        let diastolic: NumericStats
        let weight: NumericStats

        let sleep: SleepStats
        let workouts: WorkoutStats
        let medications: MedicationStats

        let sourceText: String
        let ai: NJAppleIntelligenceSummarizer.Result?
    }

    struct TrendSummary {
        let weeks: [WeekSummary]
        let trendText: String
        let ai: NJAppleIntelligenceSummarizer.Result?
    }

    struct WeekSummary {
        let startMs: Int64
        let endMs: Int64
        let summary: RangeSummary
    }

    struct NumericStats {
        let count: Int
        let min: Double?
        let max: Double?
        let avg: Double?
        let latest: Double?
        let latestTsMs: Int64?
        let unit: String
    }

    struct SleepStats {
        let asleepMs: Int64
        let inBedMs: Int64
        let sessions: Int
    }

    struct WorkoutStats {
        let count: Int
        let totalDurationSec: Double
        let totalEnergyKcal: Double
        let totalDistanceM: Double
        let byActivity: [String: ActivityStats]
    }

    struct ActivityStats {
        let count: Int
        let durationSec: Double
        let energyKcal: Double
        let distanceM: Double
    }

    struct MedicationStats {
        let count: Int
        let byName: [String: Int]
    }

    static func summarizeRange(
        db: SQLiteDB,
        start: Date,
        end: Date,
        includeAISummary: Bool = false
    ) async -> RangeSummary {
        let startMs = ms(start)
        let endMs = ms(end)

        let systolic = loadNumericStats(db: db, type: "blood_pressure_systolic", startMs: startMs, endMs: endMs, defaultUnit: "mmHg")
        let diastolic = loadNumericStats(db: db, type: "blood_pressure_diastolic", startMs: startMs, endMs: endMs, defaultUnit: "mmHg")
        let weight = loadNumericStats(db: db, type: "weight", startMs: startMs, endMs: endMs, defaultUnit: "kg")

        let sleep = loadSleepStats(db: db, startMs: startMs, endMs: endMs)
        let workouts = loadWorkoutStats(db: db, startMs: startMs, endMs: endMs)
        let meds = loadMedicationStats(db: db, startMs: startMs, endMs: endMs)

        let text = buildRangeSummaryText(
            startMs: startMs,
            endMs: endMs,
            systolic: systolic,
            diastolic: diastolic,
            weight: weight,
            sleep: sleep,
            workouts: workouts,
            medications: meds
        )

        let ai: NJAppleIntelligenceSummarizer.Result?
        if includeAISummary {
            ai = await NJAppleIntelligenceSummarizer.summarizeAuto(text: text)
        } else {
            ai = nil
        }

        return RangeSummary(
            startMs: startMs,
            endMs: endMs,
            systolic: systolic,
            diastolic: diastolic,
            weight: weight,
            sleep: sleep,
            workouts: workouts,
            medications: meds,
            sourceText: text,
            ai: ai
        )
    }

    static func summarizeWeeklyTrend(
        db: SQLiteDB,
        start: Date,
        end: Date,
        includeAISummary: Bool = false
    ) async -> TrendSummary {
        let weeks = splitIntoWeeks(start: start, end: end)
        var out: [WeekSummary] = []
        out.reserveCapacity(weeks.count)

        for w in weeks {
            let summary = await summarizeRange(db: db, start: w.start, end: w.end, includeAISummary: false)
            out.append(WeekSummary(startMs: ms(w.start), endMs: ms(w.end), summary: summary))
        }

        let trendText = buildTrendText(weeks: out)

        let ai: NJAppleIntelligenceSummarizer.Result?
        if includeAISummary {
            ai = await NJAppleIntelligenceSummarizer.summarizeAuto(text: trendText)
        } else {
            ai = nil
        }

        return TrendSummary(weeks: out, trendText: trendText, ai: ai)
    }

    // MARK: - Loaders

    private static func loadNumericStats(
        db: SQLiteDB,
        type: String,
        startMs: Int64,
        endMs: Int64,
        defaultUnit: String
    ) -> NumericStats {
        let sql = """
        SELECT start_ms, value_num, unit
        FROM health_samples
        WHERE type = '\(type)'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs)
        ORDER BY start_ms ASC;
        """

        let rows = db.queryRows(sql)
        var count = 0
        var minV: Double?
        var maxV: Double?
        var sum: Double = 0
        var latest: Double?
        var latestTs: Int64?
        var unit = defaultUnit

        for r in rows {
            guard let v = Double(r["value_num"] ?? "") else { continue }
            let ts = Int64(r["start_ms"] ?? "") ?? 0
            let u = r["unit"] ?? ""

            if !u.isEmpty { unit = u }

            count += 1
            sum += v
            minV = minV == nil ? v : min(minV!, v)
            maxV = maxV == nil ? v : max(maxV!, v)
            if latestTs == nil || ts >= (latestTs ?? 0) {
                latestTs = ts
                latest = v
            }
        }

        let avg = count > 0 ? (sum / Double(count)) : nil
        return NumericStats(
            count: count,
            min: minV,
            max: maxV,
            avg: avg,
            latest: latest,
            latestTsMs: latestTs,
            unit: unit
        )
    }

    private static func loadSleepStats(db: SQLiteDB, startMs: Int64, endMs: Int64) -> SleepStats {
        let sql = """
        SELECT start_ms, end_ms, value_str
        FROM health_samples
        WHERE type = 'sleep'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs)
        ORDER BY start_ms ASC;
        """

        let rows = db.queryRows(sql)
        var asleep: Int64 = 0
        var inBed: Int64 = 0
        var sessions = 0

        for r in rows {
            let s = Int64(r["start_ms"] ?? "") ?? 0
            let e = Int64(r["end_ms"] ?? "") ?? 0
            let value = r["value_str"] ?? ""
            let dur = max(0, e - s)

            if value == "asleep" {
                asleep += dur
            } else if value == "in_bed" {
                inBed += dur
            }
            sessions += 1
        }

        return SleepStats(asleepMs: asleep, inBedMs: inBed, sessions: sessions)
    }

    private static func loadWorkoutStats(db: SQLiteDB, startMs: Int64, endMs: Int64) -> WorkoutStats {
        let sql = """
        SELECT value_num, value_str, metadata_json
        FROM health_samples
        WHERE type = 'workout'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs)
        ORDER BY start_ms ASC;
        """

        let rows = db.queryRows(sql)
        var count = 0
        var totalDuration: Double = 0
        var totalEnergy: Double = 0
        var totalDistance: Double = 0
        var byActivity: [String: ActivityStats] = [:]

        for r in rows {
            guard let duration = Double(r["value_num"] ?? "") else { continue }
            let activity = (r["value_str"] ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
            let meta = parseJSONDict(r["metadata_json"] ?? "")
            let energy = (meta["energy_kcal"] as? NSNumber)?.doubleValue ?? 0
            let distance = (meta["distance_m"] as? NSNumber)?.doubleValue ?? 0

            count += 1
            totalDuration += duration
            totalEnergy += energy
            totalDistance += distance

            let key = activity.isEmpty ? "unknown" : activity
            let prev = byActivity[key]
            let next = ActivityStats(
                count: (prev?.count ?? 0) + 1,
                durationSec: (prev?.durationSec ?? 0) + duration,
                energyKcal: (prev?.energyKcal ?? 0) + energy,
                distanceM: (prev?.distanceM ?? 0) + distance
            )
            byActivity[key] = next
        }

        return WorkoutStats(
            count: count,
            totalDurationSec: totalDuration,
            totalEnergyKcal: totalEnergy,
            totalDistanceM: totalDistance,
            byActivity: byActivity
        )
    }

    private static func loadMedicationStats(db: SQLiteDB, startMs: Int64, endMs: Int64) -> MedicationStats {
        let doseSql = """
        SELECT COUNT(*) AS c
        FROM health_samples
        WHERE type = 'medication_dose'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs);
        """
        let doseRows = db.queryRows(doseSql)
        let doseCount = Int(doseRows.first?["c"] ?? "0") ?? 0
        if doseCount > 0 {
            return MedicationStats(count: doseCount, byName: [:])
        }

        let sql = """
        SELECT value_str
        FROM health_samples
        WHERE type = 'medication_record'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs)
        ORDER BY start_ms ASC;
        """

        let rows = db.queryRows(sql)
        var total = 0
        var byName: [String: Int] = [:]

        for r in rows {
            let name = (r["value_str"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            total += 1
            byName[name] = (byName[name] ?? 0) + 1
        }

        return MedicationStats(count: total, byName: byName)
    }

    // MARK: - Text

    private static func buildRangeSummaryText(
        startMs: Int64,
        endMs: Int64,
        systolic: NumericStats,
        diastolic: NumericStats,
        weight: NumericStats,
        sleep: SleepStats,
        workouts: WorkoutStats,
        medications: MedicationStats
    ) -> String {
        var lines: [String] = []
        lines.append("Health summary \(fmtDate(startMs)) → \(fmtDate(endMs))")

        lines.append(metricLine(name: "Blood pressure systolic", stats: systolic))
        lines.append(metricLine(name: "Blood pressure diastolic", stats: diastolic))
        lines.append(metricLine(name: "Weight", stats: weight))

        if sleep.sessions > 0 {
            lines.append("Sleep: asleep \(fmtDurMs(sleep.asleepMs)), in bed \(fmtDurMs(sleep.inBedMs)), sessions \(sleep.sessions)")
        } else {
            lines.append("Sleep: no samples")
        }

        if workouts.count > 0 {
            var w = "Workouts: \(workouts.count) sessions, total \(fmtDurSec(workouts.totalDurationSec))"
            if workouts.totalEnergyKcal > 0 { w += ", \(fmtNum(workouts.totalEnergyKcal)) kcal" }
            if workouts.totalDistanceM > 0 { w += ", \(fmtDistance(workouts.totalDistanceM))" }
            let top = topActivities(workouts.byActivity, limit: 3)
            if !top.isEmpty { w += "; top: \(top.joined(separator: ", "))" }
            lines.append(w)
        } else {
            lines.append("Workouts: none")
        }

        if medications.count > 0 {
            let top = topMedication(medications.byName, limit: 3)
            var m = "Medications: \(medications.count) records"
            if !top.isEmpty { m += "; top: \(top.joined(separator: ", "))" }
            lines.append(m)
        } else {
            lines.append("Medications: none")
        }

        return lines.joined(separator: "\n")
    }

    private static func buildTrendText(weeks: [WeekSummary]) -> String {
        guard let first = weeks.first, let last = weeks.last else { return "No data" }
        var lines: [String] = []
        lines.append("Weekly trend \(fmtDate(first.startMs)) → \(fmtDate(last.endMs))")
        lines.append("Weeks: \(weeks.count)")

        for w in weeks {
            let s = w.summary
            let header = "Week \(fmtDate(w.startMs)) → \(fmtDate(w.endMs))"
            lines.append(header)
            lines.append("  \(metricInline(label: "BP sys", stats: s.systolic))")
            lines.append("  \(metricInline(label: "BP dia", stats: s.diastolic))")
            lines.append("  \(metricInline(label: "Weight", stats: s.weight))")
            lines.append("  Sleep: \(fmtDurMs(s.sleep.asleepMs)) asleep")
            lines.append("  Workouts: \(s.workouts.count) sessions, \(fmtDurSec(s.workouts.totalDurationSec))")
        }

        let weightDelta = deltaText(weeks: weeks, key: { $0.summary.weight.avg })
        let sleepDelta = deltaText(weeks: weeks, key: { avgSleepHours($0.summary.sleep) })
        let workoutDelta = deltaText(weeks: weeks, key: { $0.summary.workouts.totalDurationSec / 3600.0 })
        let sysDelta = deltaText(weeks: weeks, key: { $0.summary.systolic.avg })

        lines.append("Trend signals")
        if let weightDelta { lines.append("  Weight avg: \(weightDelta) (kg)") }
        if let sleepDelta { lines.append("  Sleep avg: \(sleepDelta) (hours)") }
        if let workoutDelta { lines.append("  Workout time: \(workoutDelta) (hours)") }
        if let sysDelta { lines.append("  BP systolic avg: \(sysDelta) (mmHg)") }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func ms(_ d: Date) -> Int64 {
        Int64(d.timeIntervalSince1970 * 1000.0)
    }

    private static func fmtDate(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func fmtNum(_ v: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }

    private static func fmtDurMs(_ ms: Int64) -> String {
        let sec = Double(ms) / 1000.0
        return fmtDurSec(sec)
    }

    private static func fmtDurSec(_ sec: Double) -> String {
        if sec <= 0 { return "0m" }
        let totalMin = Int(sec / 60.0)
        let h = totalMin / 60
        let m = totalMin % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private static func fmtDistance(_ meters: Double) -> String {
        if meters <= 0 { return "0m" }
        if meters >= 1000 {
            return "\(fmtNum(meters / 1000.0)) km"
        }
        return "\(Int(meters)) m"
    }

    private static func metricLine(name: String, stats: NumericStats) -> String {
        guard stats.count > 0 else { return "\(name): no samples" }
        var parts: [String] = []
        if let avg = stats.avg { parts.append("avg \(fmtNum(avg))") }
        if let min = stats.min, let max = stats.max { parts.append("min \(fmtNum(min)) / max \(fmtNum(max))") }
        if let latest = stats.latest { parts.append("latest \(fmtNum(latest))") }
        parts.append("n=\(stats.count)")
        return "\(name): \(parts.joined(separator: ", ")) \(stats.unit)"
    }

    private static func metricInline(label: String, stats: NumericStats) -> String {
        guard stats.count > 0 else { return "\(label): n=0" }
        let avg = stats.avg.map(fmtNum) ?? "-"
        return "\(label): avg \(avg) \(stats.unit) n=\(stats.count)"
    }

    private static func topActivities(_ dict: [String: ActivityStats], limit: Int) -> [String] {
        let sorted = dict.sorted { a, b in
            if a.value.durationSec == b.value.durationSec { return a.key < b.key }
            return a.value.durationSec > b.value.durationSec
        }
        return sorted.prefix(limit).map { "\($0.key) \(fmtDurSec($0.value.durationSec))" }
    }

    private static func topMedication(_ dict: [String: Int], limit: Int) -> [String] {
        let sorted = dict.sorted { a, b in
            if a.value == b.value { return a.key < b.key }
            return a.value > b.value
        }
        return sorted.prefix(limit).map { "\($0.key) x\($0.value)" }
    }

    private static func parseJSONDict(_ s: String) -> [String: Any] {
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        guard let d = s.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d, options: [])) as? [String: Any] ?? [:]
    }

    private static func splitIntoWeeks(start: Date, end: Date) -> [(start: Date, end: Date)] {
        guard start < end else { return [] }
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

    private static func deltaText(weeks: [WeekSummary], key: (WeekSummary) -> Double?) -> String? {
        guard let first = weeks.first, let last = weeks.last else { return nil }
        guard let a = key(first), let b = key(last) else { return nil }
        let delta = b - a
        let dir = delta > 0 ? "up" : (delta < 0 ? "down" : "flat")
        return "\(fmtNum(a)) → \(fmtNum(b)) (\(dir) \(fmtNum(abs(delta))))"
    }

    private static func avgSleepHours(_ sleep: SleepStats) -> Double? {
        guard sleep.sessions > 0 else { return nil }
        let hours = Double(sleep.asleepMs) / 1000.0 / 3600.0
        return hours / max(1.0, Double(sleep.sessions))
    }
}
