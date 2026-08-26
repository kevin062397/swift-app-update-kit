//
//  PromptStateStore.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

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

// MARK: - User defaults-backed implementation

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
            return UserDefaultsPromptStateStore(defaults: .standard)
        }
        guard let openedDefaults = UserDefaults(suiteName: suiteName) else {
            return InMemoryPromptStateStore()
        }
        return UserDefaultsPromptStateStore(defaults: openedDefaults)
    }

    func lastCheckDate(currentDate: Date) async -> Date? {
        guard let stored = self.defaults.object(forKey: Self.lastCheckDateKey) as? Date else {
            return nil
        }
        return stored <= currentDate ? stored : nil
    }

    func recordLastCheckDate(_ date: Date) async {
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
        return expiry <= maximumAllowedFutureExpiry ? expiry : nil
    }

    func recordSnooze(for versionString: String, expiry: Date) async {
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
            stored.append(versionString)
            self.defaults.set(stored, forKey: Self.skippedVersionsKey)
        }
    }

    func pruneEntries(olderThan currentStoreVersion: AppVersion) async {
        if var snoozed = self.defaults.dictionary(forKey: Self.snoozedVersionsKey) as? [String: Double] {
            snoozed = snoozed.filter { AppVersion($0.key) >= currentStoreVersion }
            self.defaults.set(snoozed, forKey: Self.snoozedVersionsKey)
        }
        if var skipped = self.defaults.stringArray(forKey: Self.skippedVersionsKey) {
            skipped = skipped.filter { AppVersion($0) >= currentStoreVersion }
            self.defaults.set(skipped, forKey: Self.skippedVersionsKey)
        }
    }
}

// MARK: - In-memory fallback implementation

actor InMemoryPromptStateStore: PromptStateStore {
    private var storedLastCheckDate: Date?
    private var snoozedVersions: [String: Date] = [:]
    private var skippedVersions: Set<String> = []

    func lastCheckDate(currentDate: Date) async -> Date? {
        guard let stored = self.storedLastCheckDate else { return nil }
        return stored <= currentDate ? stored : nil
    }

    func recordLastCheckDate(_ date: Date) async {
        self.storedLastCheckDate = date
    }

    func snoozeExpiry(
        for versionString: String,
        currentDate: Date,
        snoozeInterval: TimeInterval
    ) async -> Date? {
        guard let expiry = self.snoozedVersions[versionString] else { return nil }
        let maximumAllowedFutureExpiry = currentDate.addingTimeInterval(snoozeInterval)
        return expiry <= maximumAllowedFutureExpiry ? expiry : nil
    }

    func recordSnooze(for versionString: String, expiry: Date) async {
        self.snoozedVersions[versionString] = expiry
    }

    func isVersionSkipped(_ versionString: String) async -> Bool {
        return self.skippedVersions.contains(versionString)
    }

    func recordSkip(for versionString: String) async {
        self.skippedVersions.insert(versionString)
    }

    func pruneEntries(olderThan currentStoreVersion: AppVersion) async {
        self.snoozedVersions = self.snoozedVersions.filter { AppVersion($0.key) >= currentStoreVersion }
        self.skippedVersions = self.skippedVersions.filter { AppVersion($0) >= currentStoreVersion }
    }
}
