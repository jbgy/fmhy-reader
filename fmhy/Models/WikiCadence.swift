//
//  WikiCadence.swift
//  fmhy
//
//  The wiki is someone else's living document: some sections are rewritten
//  daily, others sit untouched for months. A single timer either hammers the
//  API or leaves the busy sections stale, so refresh timing comes from the
//  section's own commit history.
//

import Foundation

enum WikiCadence {

    /// How old a single section's copy may be before it is re-checked on open.
    static func sectionRefreshInterval(forChurnPerWeek rate: Double) -> TimeInterval {
        if rate >= 4 { return 60 * 60 }
        if rate >= 1 { return 6 * 60 * 60 }
        if rate > 0 { return 24 * 60 * 60 }
        return 72 * 60 * 60
    }

    /// How often the app checks GitHub at all, for the whole repository.
    static func checkInterval(totalChurnPerWeek total: Double) -> TimeInterval {
        if total >= 10 { return 2 * 60 * 60 }
        if total >= 3 { return 4 * 60 * 60 }
        return 6 * 60 * 60
    }

    /// e.g. "changes ~3× a week"; nil only when no rate was measured.
    static func description(forChurnPerWeek rate: Double) -> String? {
        if rate >= 6 { return "changes daily" }
        if rate >= 2 { return "changes ~\(Int(rate.rounded()))× a week" }
        if rate >= 1 { return "changes about weekly" }
        if rate >= 0.25 { return "changes about monthly" }
        return "rarely changes"
    }

    static func tempoLine(totalChurnPerWeek total: Double) -> String {
        guard total > 0 else { return "no changes in the last month" }
        let rounded = Int(total.rounded())
        if total >= 10 { return "busy · ~\(rounded) changes a week" }
        if total >= 3 { return "steady · ~\(rounded) changes a week" }
        if total >= 1 { return "quiet · ~\(rounded) change\(rounded == 1 ? "" : "s") a week" }
        return "very quiet · under one change a week"
    }
}
