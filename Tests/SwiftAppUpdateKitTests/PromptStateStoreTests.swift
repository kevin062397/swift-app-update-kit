//
//  PromptStateStoreTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import Testing

@testable import SwiftAppUpdateKit

struct PromptStateStoreTests {
    // A fixed reference date so tests do not depend on the real system clock.
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let oneDayInSeconds: TimeInterval = 86400

    // MARK: - Snooze Expiry

    @Test func snoozeExpiryIsReturnedForSnoozedVersion() async {
        let store = InMemoryPromptStateStore()
        let expiry = self.referenceDate.addingTimeInterval(self.oneDayInSeconds)
        await store.recordSnooze(for: "1.5.0", expiry: expiry)

        let result = await store.snoozeExpiry(
            for: "1.5.0",
            currentDate: self.referenceDate,
            snoozeInterval: self.oneDayInSeconds
        )

        #expect(result == expiry)
    }

    @Test func snoozeExpiryIsNilForVersionWithNoSnoozeRecorded() async {
        let store = InMemoryPromptStateStore()

        let result = await store.snoozeExpiry(
            for: "1.5.0",
            currentDate: self.referenceDate,
            snoozeInterval: self.oneDayInSeconds
        )

        #expect(result == nil)
    }

    // MARK: - Clock-Skew Clamps

    @Test func snoozeExpiryBeyondOneIntervalInFutureIsClamped() async {
        let store = InMemoryPromptStateStore()
        // Expiry is two days in the future — more than one snooze interval ahead.
        let expiry = self.referenceDate.addingTimeInterval(self.oneDayInSeconds * 2)
        await store.recordSnooze(for: "1.5.0", expiry: expiry)

        let result = await store.snoozeExpiry(
            for: "1.5.0",
            currentDate: self.referenceDate,
            snoozeInterval: self.oneDayInSeconds
        )

        #expect(result == nil)
    }

    @Test func snoozeExpiryWithinOneIntervalInFutureIsNotClamped() async {
        let store = InMemoryPromptStateStore()
        // Expiry is twelve hours in the future — within the one-day snooze interval.
        let expiry = self.referenceDate.addingTimeInterval(self.oneDayInSeconds / 2)
        await store.recordSnooze(for: "1.5.0", expiry: expiry)

        let result = await store.snoozeExpiry(
            for: "1.5.0",
            currentDate: self.referenceDate,
            snoozeInterval: self.oneDayInSeconds
        )

        #expect(result == expiry)
    }

    @Test func futureLastCheckDateIsTreatedAsNoCheckRecorded() async {
        let store = InMemoryPromptStateStore()
        // A timestamp ahead of the queried currentDate: the device clock moved backward.
        let futureDate = self.referenceDate.addingTimeInterval(self.oneDayInSeconds)
        await store.recordLastCheckDate(futureDate)

        let result = await store.lastCheckDate(currentDate: self.referenceDate)

        #expect(result == nil)
    }

    @Test func pastLastCheckDateIsReturnedNormally() async {
        let store = InMemoryPromptStateStore()
        let pastDate = self.referenceDate.addingTimeInterval(-self.oneDayInSeconds)
        await store.recordLastCheckDate(pastDate)

        let result = await store.lastCheckDate(currentDate: self.referenceDate)

        #expect(result == pastDate)
    }

    // MARK: - Skip Persistence

    @Test func skippedVersionIsRecognizedAsSkipped() async {
        let store = InMemoryPromptStateStore()
        await store.recordSkip(for: "1.5.0")

        let result = await store.isVersionSkipped("1.5.0")

        #expect(result == true)
    }

    @Test func unskippedVersionIsNotRecognizedAsSkipped() async {
        let store = InMemoryPromptStateStore()

        let result = await store.isVersionSkipped("1.5.0")

        #expect(result == false)
    }

    @Test func newerVersionIsNotAffectedByOlderVersionSkip() async {
        let store = InMemoryPromptStateStore()
        await store.recordSkip(for: "1.5.0")

        let result = await store.isVersionSkipped("1.6.0")

        #expect(result == false)
    }

    // MARK: - Pruning

    @Test func pruningRemovesEntriesForVersionsOrderingBeforeCurrentStoreVersion() async {
        let store = InMemoryPromptStateStore()
        let expiry = self.referenceDate.addingTimeInterval(self.oneDayInSeconds)
        await store.recordSnooze(for: "1.4.0", expiry: expiry)
        await store.recordSkip(for: "1.4.0")

        await store.pruneEntries(olderThan: AppVersion("1.5.0"))

        let snoozeResult = await store.snoozeExpiry(
            for: "1.4.0",
            currentDate: self.referenceDate,
            snoozeInterval: self.oneDayInSeconds
        )
        let skipResult = await store.isVersionSkipped("1.4.0")
        #expect(snoozeResult == nil)
        #expect(skipResult == false)
    }

    @Test func pruningKeepsEntriesForCurrentStoreVersionAndNewer() async {
        let store = InMemoryPromptStateStore()
        let expiry = self.referenceDate.addingTimeInterval(self.oneDayInSeconds)
        await store.recordSnooze(for: "1.5.0", expiry: expiry)
        await store.recordSkip(for: "1.5.0")
        await store.recordSnooze(for: "1.6.0", expiry: expiry)
        await store.recordSkip(for: "1.6.0")

        await store.pruneEntries(olderThan: AppVersion("1.5.0"))

        let snooze150 = await store.snoozeExpiry(
            for: "1.5.0",
            currentDate: self.referenceDate,
            snoozeInterval: self.oneDayInSeconds
        )
        let skip150 = await store.isVersionSkipped("1.5.0")
        let snooze160 = await store.snoozeExpiry(
            for: "1.6.0",
            currentDate: self.referenceDate,
            snoozeInterval: self.oneDayInSeconds
        )
        let skip160 = await store.isVersionSkipped("1.6.0")
        #expect(snooze150 == expiry)
        #expect(skip150 == true)
        #expect(snooze160 == expiry)
        #expect(skip160 == true)
    }

    // MARK: - In-Memory Fallback

    @Test func unavailableDefaultsSuiteFallsBackToInMemoryStoreWithoutCrashing() async {
        // UserDefaults.globalDomain ("NSGlobalDomain") cannot be opened as a suite,
        // so the factory returns an in-memory store instead.
        let store = UserDefaultsPromptStateStore.make(suiteName: UserDefaults.globalDomain)
        let expiry = self.referenceDate.addingTimeInterval(self.oneDayInSeconds)
        await store.recordSnooze(for: "1.5.0", expiry: expiry)

        let result = await store.snoozeExpiry(
            for: "1.5.0",
            currentDate: self.referenceDate,
            snoozeInterval: self.oneDayInSeconds
        )

        #expect(result == expiry)
    }
}
