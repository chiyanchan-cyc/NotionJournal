//
//  NJReconstructedTagMatch.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/23.
//


import Foundation

enum NJReconstructedTagMatch: Equatable {
    case exact(String)
    case prefix(String)
}

enum NJReconstructedTimeField: Equatable {
    case blockCreatedAtMs
    case tagCreatedAtMs
}

struct NJReconstructedSpec: Equatable, Identifiable {
    let id: String

    var title: String
    var tab: String

    var match: NJReconstructedTagMatch
    var timeField: NJReconstructedTimeField

    var startMs: Int64?
    var endMs: Int64?

    var limit: Int
    var newestFirst: Bool

    static func weekly() -> NJReconstructedSpec {
        let calendar = Calendar.current
        let now = Date()
        
        // 1. Calculate the start of the current week (Sunday)
        // We set weekday to 1 (Sunday) to ensure the week always starts on Sunday regardless of locale
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear, .weekday], from: now)
        components.weekday = 1 // Sunday
        
        // If the calculated Sunday is in the future (meaning today is before Sunday in the week-of-year calculation),
        // we need to go back to the previous week.
        guard let startOfWeek = calendar.date(from: components) else {
            // Fallback to unfiltered if date calculation fails
            return NJReconstructedSpec(
                id: "recon:#WEEKLY",
                title: "WEEKLY",
                tab: "RECONSTRUCTED",
                match: .exact("#WEEKLY"),
                timeField: .blockCreatedAtMs,
                startMs: nil,
                endMs: nil,
                limit: 500,
                newestFirst: true
            )
        }
        
        if startOfWeek > now {
            // Go back 1 week to get the current period's Sunday
            // Using weekOfYear = 1 handles the week wrapping automatically
            components.weekOfYear = 1
            components.weekday = 1
        }
        
        // Re-fetch with the potentially adjusted components
        let finalStartOfWeek = calendar.date(from: components) ?? startOfWeek
        
        // 2. Calculate the end of the week (Saturday) by adding 6 days to Sunday
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: finalStartOfWeek) ?? finalStartOfWeek
        
        // 3. Convert to milliseconds for the database query
        let startMs = Int64(finalStartOfWeek.timeIntervalSince1970 * 1000)
        let endMs = Int64(endOfWeek.timeIntervalSince1970 * 1000)
        
        // 4. Create the spec with the calculated time range
        return NJReconstructedSpec(
            id: "recon:#WEEKLY",
            title: "WEEKLY",
            tab: "RECONSTRUCTED",
            match: .exact("#WEEKLY"),
            timeField: .blockCreatedAtMs,
            startMs: startMs,
            endMs: endMs,
            limit: 500,
            newestFirst: true
        )
    }

    static func tagExact(_ tag: String, startMs: Int64? = nil, endMs: Int64? = nil, timeField: NJReconstructedTimeField = .blockCreatedAtMs, limit: Int = 500, newestFirst: Bool = true) -> NJReconstructedSpec {
        NJReconstructedSpec(
            id: "recon:exact:\(tag):\(startMs ?? 0):\(endMs ?? 0):\(timeField)",
            title: tag,
            tab: "RECONSTRUCTED",
            match: .exact(tag),
            timeField: timeField,
            startMs: startMs,
            endMs: endMs,
            limit: limit,
            newestFirst: newestFirst
        )
    }

    static func tagPrefix(_ prefix: String, startMs: Int64? = nil, endMs: Int64? = nil, timeField: NJReconstructedTimeField = .blockCreatedAtMs, limit: Int = 500, newestFirst: Bool = true) -> NJReconstructedSpec {
        NJReconstructedSpec(
            id: "recon:prefix:\(prefix):\(startMs ?? 0):\(endMs ?? 0):\(timeField)",
            title: prefix,
            tab: "RECONSTRUCTED",
            match: .prefix(prefix),
            timeField: timeField,
            startMs: startMs,
            endMs: endMs,
            limit: limit,
            newestFirst: newestFirst
        )
    }
}
