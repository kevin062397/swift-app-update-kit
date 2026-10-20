//
//  UpdateCheckerTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import Testing

@testable import SwiftAppUpdateKit

// MARK: - Mocks

private struct CheckerMockBuildEnvironmentDetector: BuildEnvironmentDetector {
    let environment: AppBuildEnvironment
    func currentEnvironment() async -> AppBuildEnvironment {
        return self.environment
    }
}

private actor CheckerMockUpdateSource: UpdateSource {
    enum MockResult {
        case success(AppStoreMetadata)
        case failure(LookupRequestError)
    }

    private let mockResult: MockResult
    private(set) var callCount = 0

    init(result: MockResult) {
        self.mockResult = result
    }

    func fetchMetadata(
        bundleIdentifier _: String,
        storefrontCountryCode _: String?,
        languageCodes _: [String]
    ) async throws(LookupRequestError) -> AppStoreMetadata {
        self.callCount += 1
        switch self.mockResult {
        case .success(let metadata):
            return metadata
        case .failure(let error):
            throw error
        }
    }
}

/// A mock that returns successive metadata values on each call, for testing supersession.
private actor SequencedMockUpdateSource: UpdateSource {
    private let metadataSequence: [AppStoreMetadata]
    private var callIndex = 0
    private(set) var callCount = 0

    init(sequence: [AppStoreMetadata]) {
        self.metadataSequence = sequence
    }

    func fetchMetadata(
        bundleIdentifier _: String,
        storefrontCountryCode _: String?,
        languageCodes _: [String]
    ) async throws(LookupRequestError) -> AppStoreMetadata {
        self.callCount += 1
        let metadata = self.metadataSequence[min(self.callIndex, self.metadataSequence.count - 1)]
        self.callIndex += 1
        return metadata
    }
}

private struct CheckerMockStorefrontResolver: StorefrontResolver {
    func resolveStorefrontCountryCode() async -> String? {
        return "US"
    }
}

private struct CheckerMockAppStoreLanguageResolver: AppStoreLanguageResolver {
    func resolveLanguageCodes() -> [String] {
        return ["en_us"]
    }
}

private actor URLOpenRecord {
    private(set) var openedURLs: [URL] = []
    private let successSequence: [Bool]
    private var callIndex = 0

    init(successSequence: [Bool] = [true]) {
        self.successSequence = successSequence
    }

    func record(url: URL) -> Bool {
        self.openedURLs.append(url)
        let success =
            self.callIndex < self.successSequence.count
            ? self.successSequence[self.callIndex]
            : self.successSequence.last ?? true
        self.callIndex += 1
        return success
    }
}

private struct MockURLOpener: URLOpener {
    let record: URLOpenRecord

    @MainActor
    func open(_ url: URL) async -> Bool {
        await self.record.record(url: url)
    }
}

// MARK: - Tests

@MainActor struct UpdateCheckerTests {
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private static let installedVersionString = "1.4.2"
    private static let storeVersionString = "1.5.0"
    private static let newerStoreVersionString = "1.6.0"

    private static let allOptionalPolicy = UpdatePolicy(
        major: .optional,
        minor: .optional,
        patch: .optional,
        revision: .optional
    )

    private func makeStoreMetadata(versionString: String = storeVersionString) -> AppStoreMetadata {
        AppStoreMetadata(
            trackID: 123_456,
            versionString: versionString,
            version: AppVersion(versionString),
            minimumOperatingSystemVersion: AppVersion("17.0"),
            releaseDate: Date(timeIntervalSinceReferenceDate: 0),
            productPageURL: URL(string: "https://apps.apple.com/app/id123456")!,
            releaseNotes: nil,
            artworkURL: nil,
            fileSizeInBytes: nil
        )
    }

    private func makeChecker(
        updateSource: any UpdateSource,
        promptStateStore: any PromptStateStore = InMemoryPromptStateStore(),
        environment: AppBuildEnvironment = .production,
        urlOpener: any URLOpener = MockURLOpener(record: URLOpenRecord())
    ) -> UpdateChecker {
        let installedVersionString = Self.installedVersionString
        return UpdateChecker(
            configuration: UpdateCheckConfiguration(policy: Self.allOptionalPolicy),
            promptStateStore: promptStateStore,
            buildEnvironmentDetector: CheckerMockBuildEnvironmentDetector(environment: environment),
            updateSource: updateSource,
            storefrontResolver: CheckerMockStorefrontResolver(),
            appStoreLanguageResolver: CheckerMockAppStoreLanguageResolver(),
            urlOpener: urlOpener,
            currentDate: { self.referenceDate },
            currentOSVersion: { AppVersion("17.0") },
            bundleMetadataProvider: {
                BundleMetadata(
                    bundleIdentifier: "com.example.app",
                    installedVersionString: installedVersionString,
                    installedVersion: AppVersion(installedVersionString)
                )
            }
        )
    }

    // MARK: - Pending Update and Durability

    @Test func checkSetsPendingUpdateWhenUpdateIsAvailable() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        let outcome = try await checker.check()

        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        #expect(checker.isUpdatePromptReady)
        #expect(checker.availableUpdate == description)
    }

    @Test func pendingUpdateRemainsSetAfterCheckCompletes() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()

        #expect(checker.isUpdatePromptReady)
        #expect(checker.availableUpdate?.storeVersionString == Self.storeVersionString)
    }

    @Test func lastOutcomeIsRecordedAfterEachCheck() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        let outcome = try await checker.check()

        #expect(checker.lastOutcome == outcome)
    }

    // MARK: - Serialization

    @Test func concurrentChecksSerializeToOneNetworkRequest() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        // Both child tasks run on the main actor. The first suspends at the
        // pipeline's network await, freeing the main actor for the second, which
        // then joins the in-flight task rather than issuing a new request.
        async let result1 = checker.check()
        async let result2 = checker.check()
        let (outcome1, outcome2) = try await (result1, result2)

        #expect(outcome1 == outcome2)
        #expect(await source.callCount == 1)
    }

    // MARK: - Supersession

    @Test func newerStoreVersionSupersedesPendingUpdate() async throws {
        let source = SequencedMockUpdateSource(sequence: [
            self.makeStoreMetadata(versionString: Self.storeVersionString),
            self.makeStoreMetadata(versionString: Self.newerStoreVersionString),
        ])
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()
        #expect(checker.availableUpdate?.storeVersionString == Self.storeVersionString)

        // Override throttle to force a second network request within the same session.
        _ = try await checker.check(shouldBypassThrottle: true)
        #expect(checker.availableUpdate?.storeVersionString == Self.newerStoreVersionString)
    }

    @Test func supersessionWritesNoSuppressionForReplacedVersion() async throws {
        let store = InMemoryPromptStateStore()
        let source = SequencedMockUpdateSource(sequence: [
            self.makeStoreMetadata(versionString: Self.storeVersionString),
            self.makeStoreMetadata(versionString: Self.newerStoreVersionString),
        ])
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        _ = try await checker.check()
        _ = try await checker.check(shouldBypassThrottle: true)

        // The superseded version must have no suppression written against it.
        let isSkipped = await store.isVersionSkipped(Self.storeVersionString)
        let snoozeExpiry = await store.snoozeExpiry(
            for: Self.storeVersionString,
            currentDate: self.referenceDate,
            snoozeInterval: 86400
        )
        #expect(isSkipped == false)
        #expect(snoozeExpiry == nil)
    }

    @Test func sameVersionSecondCheckDoesNotReplacePendingUpdate() async throws {
        let source = SequencedMockUpdateSource(sequence: [
            self.makeStoreMetadata(versionString: Self.storeVersionString),
            self.makeStoreMetadata(versionString: Self.storeVersionString),
        ])
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()
        let firstUpdate = checker.availableUpdate

        _ = try await checker.check(shouldBypassThrottle: true)
        let secondUpdate = checker.availableUpdate

        #expect(firstUpdate == secondUpdate)
    }

    // MARK: - Presentation State

    @Test func checkSetsStateToAwaitingPermissionWhenUpdateIsAvailable() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()

        #expect(checker.presentationState == .awaitingPermission)
    }

    @Test func claimTransitionsToPresenting() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()
        let claimed = checker.claimUpdatePrompt()

        #expect(claimed != nil)
        #expect(checker.presentationState == .presenting)
    }

    @Test func releaseTransitionsFromPresentingToAwaitingPermission() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()
        _ = checker.claimUpdatePrompt()
        checker.releaseUpdatePrompt()

        #expect(checker.presentationState == .awaitingPermission)
        #expect(checker.isUpdatePromptReady)
    }

    @Test func secondClaimWhilePresentingReturnsNil() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()
        _ = checker.claimUpdatePrompt()
        let secondClaim = checker.claimUpdatePrompt()

        #expect(secondClaim == nil)
        #expect(checker.presentationState == .presenting)
    }

    // MARK: - Actions: Snooze

    @Test func snoozeWritesSnoozeExpiryForTheVersion() async throws {
        let store = InMemoryPromptStateStore()
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        let outcome = try await checker.check()
        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        await checker.snooze(description)

        let expiry = await store.snoozeExpiry(
            for: Self.storeVersionString,
            currentDate: self.referenceDate,
            snoozeInterval: 86400
        )
        #expect(expiry != nil)
        #expect(!checker.isUpdatePromptReady)
        #expect(checker.presentationState == .resolved)
    }

    @Test func snoozeWritesNoSkip() async throws {
        let store = InMemoryPromptStateStore()
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        let outcome = try await checker.check()
        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        await checker.snooze(description)

        let isSkipped = await store.isVersionSkipped(Self.storeVersionString)
        #expect(isSkipped == false)
    }

    // MARK: - Actions: Skip

    @Test func skipWritesPermanentSkipForTheVersion() async throws {
        let store = InMemoryPromptStateStore()
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        let outcome = try await checker.check()
        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        await checker.skip(description)

        let isSkipped = await store.isVersionSkipped(Self.storeVersionString)
        #expect(isSkipped == true)
        #expect(!checker.isUpdatePromptReady)
        #expect(checker.presentationState == .resolved)
    }

    @Test func skipWritesNoSnooze() async throws {
        let store = InMemoryPromptStateStore()
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        let outcome = try await checker.check()
        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        await checker.skip(description)

        let snoozeExpiry = await store.snoozeExpiry(
            for: Self.storeVersionString,
            currentDate: self.referenceDate,
            snoozeInterval: 86400
        )
        #expect(snoozeExpiry == nil)
    }

    // MARK: - Available Update

    @Test func checkSetsAvailableUpdateWhenUpdateIsAvailable() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        let outcome = try await checker.check()

        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        #expect(checker.availableUpdate == description)
    }

    @Test func snoozeDoesNotClearAvailableUpdate() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        let outcome = try await checker.check()
        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        await checker.snooze(description)

        #expect(!checker.isUpdatePromptReady)
        #expect(checker.availableUpdate == description)
    }

    @Test func skipDoesNotClearAvailableUpdate() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        let outcome = try await checker.check()
        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        await checker.skip(description)

        #expect(!checker.isUpdatePromptReady)
        #expect(checker.availableUpdate == description)
    }

    @Test func snoozedVersionSetsAvailableUpdateOnNextCheck() async throws {
        let store = InMemoryPromptStateStore()
        let expiry = self.referenceDate.addingTimeInterval(3600)
        await store.recordSnooze(for: Self.storeVersionString, expiry: expiry)
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        _ = try await checker.check(shouldBypassThrottle: true)

        #expect(checker.availableUpdate?.storeVersionString == Self.storeVersionString)
        #expect(!checker.isUpdatePromptReady)
    }

    @Test func skippedVersionSetsAvailableUpdateOnNextCheck() async throws {
        let store = InMemoryPromptStateStore()
        await store.recordSkip(for: Self.storeVersionString)
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        _ = try await checker.check(shouldBypassThrottle: true)

        #expect(checker.availableUpdate?.storeVersionString == Self.storeVersionString)
        #expect(!checker.isUpdatePromptReady)
    }

    @Test func upToDateCheckClearsAvailableUpdate() async throws {
        let source = SequencedMockUpdateSource(sequence: [
            self.makeStoreMetadata(versionString: Self.storeVersionString),
            self.makeStoreMetadata(versionString: Self.installedVersionString),
        ])
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()
        #expect(checker.availableUpdate != nil)

        _ = try await checker.check(shouldBypassThrottle: true)
        #expect(checker.availableUpdate == nil)
        #expect(!checker.isUpdatePromptReady)
    }

    @Test func installedIsNewerCheckClearsAvailableUpdate() async throws {
        let source = SequencedMockUpdateSource(sequence: [
            self.makeStoreMetadata(versionString: Self.storeVersionString),
            self.makeStoreMetadata(versionString: "1.3.0"),  // older than installed 1.4.2
        ])
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()
        #expect(checker.availableUpdate != nil)
        #expect(checker.isUpdatePromptReady)

        _ = try await checker.check(shouldBypassThrottle: true)
        #expect(checker.availableUpdate == nil)
        #expect(!checker.isUpdatePromptReady)
    }

    @Test func silentPolicySetsAvailableUpdateWithoutPrompt() async throws {
        let allSilentPolicy = UpdatePolicy(
            major: .silent,
            minor: .silent,
            patch: .silent,
            revision: .silent
        )
        let installedVersionString = Self.installedVersionString
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = UpdateChecker(
            configuration: UpdateCheckConfiguration(policy: allSilentPolicy),
            promptStateStore: InMemoryPromptStateStore(),
            buildEnvironmentDetector: CheckerMockBuildEnvironmentDetector(environment: .production),
            updateSource: source,
            storefrontResolver: CheckerMockStorefrontResolver(),
            appStoreLanguageResolver: CheckerMockAppStoreLanguageResolver(),
            urlOpener: MockURLOpener(record: URLOpenRecord()),
            currentDate: { self.referenceDate },
            currentOSVersion: { AppVersion("17.0") },
            bundleMetadataProvider: {
                BundleMetadata(
                    bundleIdentifier: "com.example.app",
                    installedVersionString: installedVersionString,
                    installedVersion: AppVersion(installedVersionString)
                )
            }
        )

        _ = try await checker.check(shouldBypassThrottle: true)

        #expect(checker.availableUpdate?.storeVersionString == Self.storeVersionString)
        #expect(!checker.isUpdatePromptReady)
    }

    @Test func throttledCheckLeavesAvailableUpdateUnchanged() async throws {
        let store = InMemoryPromptStateStore()
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        _ = try await checker.check()
        let firstAvailableUpdate = checker.availableUpdate
        #expect(firstAvailableUpdate != nil)

        _ = try await checker.check()
        #expect(checker.availableUpdate == firstAvailableUpdate)
    }

    // MARK: - Actions: Update Now

    @Test func updateNowOpensAppStoreURLFirst() async throws {
        let urlRecord = URLOpenRecord(successSequence: [true])
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, urlOpener: MockURLOpener(record: urlRecord))

        let outcome = try await checker.check()
        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        await checker.updateNow(for: description)

        let openedURLs = await urlRecord.openedURLs
        #expect(openedURLs.count == 1)
        #expect(openedURLs.first?.scheme == "itms-apps")
    }

    @Test func updateNowFallsBackToProductPageWhenSchemeFails() async throws {
        let urlRecord = URLOpenRecord(successSequence: [false, true])
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, urlOpener: MockURLOpener(record: urlRecord))

        let outcome = try await checker.check()
        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        await checker.updateNow(for: description)

        let openedURLs = await urlRecord.openedURLs
        #expect(openedURLs.count == 2)
        #expect(openedURLs.first?.scheme == "itms-apps")
        #expect(openedURLs.last?.scheme == "https")
    }

    @Test func updateNowWritesNoSuppression() async throws {
        let store = InMemoryPromptStateStore()
        let urlRecord = URLOpenRecord(successSequence: [true])
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(
            updateSource: source,
            promptStateStore: store,
            urlOpener: MockURLOpener(record: urlRecord)
        )

        let outcome = try await checker.check()
        guard case .updatePromptReady(let description) = outcome else {
            Issue.record("Expected updatePromptReady, got \(outcome)")
            return
        }
        await checker.updateNow(for: description)

        let isSkipped = await store.isVersionSkipped(Self.storeVersionString)
        let snoozeExpiry = await store.snoozeExpiry(
            for: Self.storeVersionString,
            currentDate: self.referenceDate,
            snoozeInterval: 86400
        )
        #expect(isSkipped == false)
        #expect(snoozeExpiry == nil)
        // The sheet stays on screen while the user is in the App Store, so the update stays pending.
        #expect(checker.isUpdatePromptReady)
    }
}
