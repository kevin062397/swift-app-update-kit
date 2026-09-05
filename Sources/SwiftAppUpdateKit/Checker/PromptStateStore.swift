//
//  PromptStateStore.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import OSLog

// MARK: - Protocol

protocol PromptStateStore: Sendable {
    /// Returns the date of the last successful check, or `nil` when none is recorded.
    ///
    /// Clock-skew clamp: a stored timestamp in the future of `currentDate` is treated as
    /// though no check has been recorded, so a backward clock shift cannot silence checking
    /// for the length of the offset.
    func lastCheckDate(currentDate: Date) async -> Date?

    /// Writes the date of the most recent successful check.
    func recordLastCheckDate(_ date: Date) async

    /// Returns the snooze expiry for the given version string, or `nil` when none is recorded.
    ///
    /// Clock-skew clamp: a stored expiry more than one `snoozeInterval` ahead of `currentDate`
    /// is treated as already expired, so no version can be silenced beyond the interval the
    /// user actually chose.
    func snoozeExpiry(
        for versionString: String,
        currentDate: Date,
        snoozeInterval: TimeInterval
    ) async -> Date?

    /// Writes a snooze for the given version string with the given expiry.
    func recordSnooze(for versionString: String, expiry: Date) async

    /// Returns whether the given version string has been permanently skipped.
    func isVersionSkipped(_ versionString: String) async -> Bool

    /// Records a permanent skip for the given version string.
    func recordSkip(for versionString: String) async

    /// Removes all snoozed and skipped entries for versions that order before
    /// `currentStoreVersion`.
    func pruneEntries(olderThan currentStoreVersion: AppVersion) async
}

// MARK: - User Defaults-Backed Implementation

actor UserDefaultsPromptStateStore: PromptStateStore {
    private static let lastCheckDateKey = "com.swiftappupdatekit.lastCheckDate"
    private static let snoozedVersionsKey = "com.swiftappupdatekit.snoozedVersions"
    private static let skippedVersionsKey = "com.swiftappupdatekit.skippedVersions"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Returns a store backed by the given suite name, or `UserDefaults.standard` when `nil`.
    ///
    /// Falls back to an in-memory store — and logs at fault level — when the suite cannot
    /// be opened.
    static func make(suiteName: String? = nil) -> any PromptStateStore {
        guard let suiteName else {
            Logger.promptStateStore.debug("[\(Self.self)] \(#function): Using standard UserDefaults store")
            return UserDefaultsPromptStateStore(defaults: .standard)
        }
        guard let openedDefaults = UserDefaults(suiteName: suiteName) else {
            Logger.promptStateStore.error(
                "[\(Self.self)] \(#function): Failed to open UserDefaults suite \(suiteName, privacy: .public); using in-memory fallback"
            )
            return InMemoryPromptStateStore()
        }
        Logger.promptStateStore.debug(
            "[\(Self.self)] \(#function): Using UserDefaults suite \(suiteName, privacy: .public)"
        )
        return UserDefaultsPromptStateStore(defaults: openedDefaults)
    }

    func lastCheckDate(currentDate: Date) async -> Date? {
        guard let stored = self.defaults.object(forKey: Self.lastCheckDateKey) as? Date else {
            return nil
        }
        guard stored <= currentDate else {
            Logger.promptStateStore.warning(
                "[\(Self.self)] \(#function): Ignoring future last-check date \(String(describing: stored), privacy: .public)"
            )
            return nil
        }
        return stored
    }

    func recordLastCheckDate(_ date: Date) async {
        Logger.promptStateStore.debug(
            "[\(Self.self)] \(#function): Recording last-check date \(String(describing: date), privacy: .public)"
        )
        self.defaults.set(date, forKey: Self.lastCheckDateKey)
    }

    func snoozeExpiry(
        for versionString: String,
        currentDate: Date,
        snoozeInterval: TimeInterval
    ) async -> Date? {
        let stored = self.defaults.dictionary(forKey: Self.snoozedVersionsKey) as? [String: Double] ?? [:]
        guard let timestamp = stored[versionString] else { return nil }
        let expiry = Date(timeIntervalSinceReferenceDate: timestamp)
        let maximumAllowedFutureExpiry = currentDate.addingTimeInterval(snoozeInterval)
        guard expiry <= maximumAllowedFutureExpiry else {
            Logger.promptStateStore.warning(
                "[\(Self.self)] \(#function): Ignoring excessive snooze expiry for \(versionString, privacy: .public): \(String(describing: expiry), privacy: .public)"
            )
            return nil
        }
        return expiry
    }

    func recordSnooze(for versionString: String, expiry: Date) async {
        Logger.promptStateStore.debug(
            "[\(Self.self)] \(#function): Recording snooze for \(versionString, privacy: .public) until \(String(describing: expiry), privacy: .public)"
        )
        var stored = self.defaults.dictionary(forKey: Self.snoozedVersionsKey) as? [String: Double] ?? [:]
        stored[versionString] = expiry.timeIntervalSinceReferenceDate
        self.defaults.set(stored, forKey: Self.snoozedVersionsKey)
    }

    func isVersionSkipped(_ versionString: String) async -> Bool {
        let stored = self.defaults.stringArray(forKey: Self.skippedVersionsKey) ?? []
        return stored.contains(versionString)
    }

    func recordSkip(for versionString: String) async {
        var stored = self.defaults.stringArray(forKey: Self.skippedVersionsKey) ?? []
        if !stored.contains(versionString) {
            Logger.promptStateStore.debug(
                "[\(Self.self)] \(#function): Recording skip for \(versionString, privacy: .public)"
            )
            stored.append(versionString)
            self.defaults.set(stored, forKey: Self.skippedVersionsKey)
        } else {
            Logger.promptStateStore.debug(
                "[\(Self.self)] \(#function): Skip for \(versionString, privacy: .public) already recorded"
            )
        }
    }

    func pruneEntries(olderThan currentStoreVersion: AppVersion) async {
        if var snoozed = self.defaults.dictionary(forKey: Self.snoozedVersionsKey) as? [String: Double] {
            let originalCount = snoozed.count
            snoozed = snoozed.filter { AppVersion($0.key) >= currentStoreVersion }
            Logger.promptStateStore.debug(
                "[\(Self.self)] \(#function): Pruned \(originalCount - snoozed.count, privacy: .public) snoozed version entries older than \(String(describing: currentStoreVersion), privacy: .public)"
            )
            self.defaults.set(snoozed, forKey: Self.snoozedVersionsKey)
        }
        if var skipped = self.defaults.stringArray(forKey: Self.skippedVersionsKey) {
            let originalCount = skipped.count
            skipped = skipped.filter { AppVersion($0) >= currentStoreVersion }
            Logger.promptStateStore.debug(
                "[\(Self.self)] \(#function): Pruned \(originalCount - skipped.count, privacy: .public) skipped version entries older than \(String(describing: currentStoreVersion), privacy: .public)"
            )
            self.defaults.set(skipped, forKey: Self.skippedVersionsKey)
        }
    }
}

// MARK: - In-Memory Fallback Implementation

actor InMemoryPromptStateStore: PromptStateStore {
    private var storedLastCheckDate: Date?
    private var snoozedVersions: [String: Date] = [:]
    private var skippedVersions: Set<String> = []

    func lastCheckDate(currentDate: Date) async -> Date? {
        guard let stored = self.storedLastCheckDate else { return nil }
        guard stored <= currentDate else {
            Logger.promptStateStore.warning(
                "[\(Self.self)] \(#function): Ignoring future last-check date \(String(describing: stored), privacy: .public)"
            )
            return nil
        }
        return stored
    }

    func recordLastCheckDate(_ date: Date) async {
        Logger.promptStateStore.debug(
            "[\(Self.self)] \(#function): Recording in-memory last-check date \(String(describing: date), privacy: .public)"
        )
        self.storedLastCheckDate = date
    }

    func snoozeExpiry(
        for versionString: String,
        currentDate: Date,
        snoozeInterval: TimeInterval
    ) async -> Date? {
        guard let expiry = self.snoozedVersions[versionString] else { return nil }
        let maximumAllowedFutureExpiry = currentDate.addingTimeInterval(snoozeInterval)
        guard expiry <= maximumAllowedFutureExpiry else {
            Logger.promptStateStore.warning(
                "[\(Self.self)] \(#function): Ignoring excessive snooze expiry for \(versionString, privacy: .public): \(String(describing: expiry), privacy: .public)"
            )
            return nil
        }
        return expiry
    }

    func recordSnooze(for versionString: String, expiry: Date) async {
        Logger.promptStateStore.debug(
            "[\(Self.self)] \(#function): Recording in-memory snooze for \(versionString, privacy: .public) until \(String(describing: expiry), privacy: .public)"
        )
        self.snoozedVersions[versionString] = expiry
    }

    func isVersionSkipped(_ versionString: String) async -> Bool {
        return self.skippedVersions.contains(versionString)
    }

    func recordSkip(for versionString: String) async {
        Logger.promptStateStore.debug(
            "[\(Self.self)] \(#function): Recording in-memory skip for \(versionString, privacy: .public)"
        )
        self.skippedVersions.insert(versionString)
    }

    func pruneEntries(olderThan currentStoreVersion: AppVersion) async {
        let originalSnoozedCount = self.snoozedVersions.count
        let originalSkippedCount = self.skippedVersions.count
        self.snoozedVersions = self.snoozedVersions.filter { AppVersion($0.key) >= currentStoreVersion }
        self.skippedVersions = self.skippedVersions.filter { AppVersion($0) >= currentStoreVersion }
        Logger.promptStateStore.debug(
            "[\(Self.self)] \(#function): Pruned \(originalSnoozedCount - self.snoozedVersions.count, privacy: .public) in-memory snoozed entries and \(originalSkippedCount - self.skippedVersions.count, privacy: .public) skipped entries older than \(String(describing: currentStoreVersion), privacy: .public)"
        )
    }
}
