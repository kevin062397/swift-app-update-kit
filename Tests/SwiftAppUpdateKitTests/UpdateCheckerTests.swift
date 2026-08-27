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
    let isProduction: Bool
    func isProductionBuild() async -> Bool {
        return self.isProduction
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
        storefrontCountryCode _: String?
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
        storefrontCountryCode _: String?
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
        isProduction: Bool = true,
        urlOpener: any URLOpener = MockURLOpener(record: URLOpenRecord())
    ) -> UpdateChecker {
        let installedVersionString = Self.installedVersionString
        return UpdateChecker(
            configuration: UpdateCheckConfiguration(policy: Self.allOptionalPolicy),
            promptStateStore: promptStateStore,
            buildEnvironmentDetector: CheckerMockBuildEnvironmentDetector(isProduction: isProduction),
            updateSource: updateSource,
            storefrontResolver: CheckerMockStorefrontResolver(),
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

    // MARK: - Pending update and durability

    @Test func checkSetsPendingUpdateWhenUpdateIsAvailable() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        let outcome = try await checker.check()

        guard case .updateAvailable(let description) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
            return
        }
        #expect(checker.pendingUpdate == description)
    }

    @Test func pendingUpdateRemainsSetAfterCheckCompletes() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()

        #expect(checker.pendingUpdate?.storeVersionString == Self.storeVersionString)
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
        #expect(checker.pendingUpdate?.storeVersionString == Self.storeVersionString)

        // Override throttle to force a second network request within the same session.
        _ = try await checker.check(overridingThrottle: true)
        #expect(checker.pendingUpdate?.storeVersionString == Self.newerStoreVersionString)
    }

    @Test func supersessionWritesNoSuppressionForReplacedVersion() async throws {
        let store = InMemoryPromptStateStore()
        let source = SequencedMockUpdateSource(sequence: [
            self.makeStoreMetadata(versionString: Self.storeVersionString),
            self.makeStoreMetadata(versionString: Self.newerStoreVersionString),
        ])
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        _ = try await checker.check()
        _ = try await checker.check(overridingThrottle: true)

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
        let firstPending = checker.pendingUpdate

        _ = try await checker.check(overridingThrottle: true)
        let secondPending = checker.pendingUpdate

        #expect(firstPending == secondPending)
    }

    // MARK: - Presentation state

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
        let claimed = checker.claimPendingUpdate()

        #expect(claimed != nil)
        #expect(checker.presentationState == .presenting)
    }

    @Test func releaseTransitionsFromPresentingToAwaitingPermission() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()
        _ = checker.claimPendingUpdate()
        checker.releasePendingUpdate()

        #expect(checker.presentationState == .awaitingPermission)
        #expect(checker.pendingUpdate != nil)
    }

    @Test func secondClaimWhilePresentingReturnsNil() async throws {
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source)

        _ = try await checker.check()
        _ = checker.claimPendingUpdate()
        let secondClaim = checker.claimPendingUpdate()

        #expect(secondClaim == nil)
        #expect(checker.presentationState == .presenting)
    }

    // MARK: - Actions: snooze

    @Test func snoozeWritesSnoozeExpiryForTheVersion() async throws {
        let store = InMemoryPromptStateStore()
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        let outcome = try await checker.check()
        guard case .updateAvailable(let description) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
            return
        }
        await checker.snooze(description)

        let expiry = await store.snoozeExpiry(
            for: Self.storeVersionString,
            currentDate: self.referenceDate,
            snoozeInterval: 86400
        )
        #expect(expiry != nil)
        #expect(checker.pendingUpdate == nil)
        #expect(checker.presentationState == .resolved)
    }

    @Test func snoozeWritesNoSkip() async throws {
        let store = InMemoryPromptStateStore()
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        let outcome = try await checker.check()
        guard case .updateAvailable(let description) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
            return
        }
        await checker.snooze(description)

        let isSkipped = await store.isVersionSkipped(Self.storeVersionString)
        #expect(isSkipped == false)
    }

    // MARK: - Actions: skip

    @Test func skipWritesPermanentSkipForTheVersion() async throws {
        let store = InMemoryPromptStateStore()
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        let outcome = try await checker.check()
        guard case .updateAvailable(let description) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
            return
        }
        await checker.skip(description)

        let isSkipped = await store.isVersionSkipped(Self.storeVersionString)
        #expect(isSkipped == true)
        #expect(checker.pendingUpdate == nil)
        #expect(checker.presentationState == .resolved)
    }

    @Test func skipWritesNoSnooze() async throws {
        let store = InMemoryPromptStateStore()
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, promptStateStore: store)

        let outcome = try await checker.check()
        guard case .updateAvailable(let description) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
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

    // MARK: - Actions: update now

    @Test func updateNowOpensAppStoreURLFirst() async throws {
        let urlRecord = URLOpenRecord(successSequence: [true])
        let source = CheckerMockUpdateSource(result: .success(self.makeStoreMetadata()))
        let checker = self.makeChecker(updateSource: source, urlOpener: MockURLOpener(record: urlRecord))

        let outcome = try await checker.check()
        guard case .updateAvailable(let description) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
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
        guard case .updateAvailable(let description) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
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
        guard case .updateAvailable(let description) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
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
        #expect(checker.pendingUpdate != nil)
    }
}
