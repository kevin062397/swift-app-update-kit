//
//  UpdateCheckPipelineTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import Testing

@testable import SwiftAppUpdateKit

// MARK: - Mocks

private struct MockBuildEnvironmentDetector: BuildEnvironmentDetector {
    let isProduction: Bool
    func isProductionBuild() async -> Bool {
        return self.isProduction
    }
}

private actor MockUpdateSource: UpdateSource {
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

private struct MockStorefrontResolver: StorefrontResolver {
    func resolveStorefrontCountryCode() async -> String? {
        return "US"
    }
}

// MARK: - Tests

struct UpdateCheckPipelineTests {
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let oneDayInSeconds: TimeInterval = 86400

    private static let installedVersionString = "1.4.2"
    private static let storeVersionString = "1.5.0"

    private static let allOptionalPolicy = UpdatePolicy(
        major: .optional,
        minor: .optional,
        patch: .optional,
        revision: .optional
    )

    private func makeStoreMetadata(
        versionString: String = storeVersionString,
        minimumOSVersionString: String = "17.0",
        releaseDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> AppStoreMetadata {
        return AppStoreMetadata(
            trackID: 123_456,
            versionString: versionString,
            version: AppVersion(versionString),
            minimumOperatingSystemVersion: AppVersion(minimumOSVersionString),
            releaseDate: releaseDate,
            productPageURL: URL(string: "https://apps.apple.com/app/id123456")!,
            releaseNotes: nil,
            artworkURL: nil,
            fileSizeInBytes: nil
        )
    }

    private func makeBundleMetadata(
        versionString: String = installedVersionString
    ) -> BundleMetadata {
        return BundleMetadata(
            bundleIdentifier: "com.example.app",
            installedVersionString: versionString,
            installedVersion: AppVersion(versionString)
        )
    }

    private func makePipeline(
        policy: UpdatePolicy = allOptionalPolicy,
        promptStateStore: any PromptStateStore,
        isProduction: Bool = true,
        bundleMetadata: BundleMetadata? = nil,
        updateSource: any UpdateSource,
        currentDate: Date,
        currentOSVersionString: String = "17.0",
        overridesThrottle: Bool = false,
        throttleInterval: TimeInterval = 86400,
        snoozeInterval: TimeInterval = 86400,
        minimumReleaseAge: TimeInterval = 86400
    ) -> UpdateCheckPipeline {
        let resolvedBundleMetadata = bundleMetadata ?? self.makeBundleMetadata()
        return UpdateCheckPipeline(
            configuration: UpdateCheckConfiguration(
                policy: policy,
                throttleInterval: throttleInterval,
                snoozeInterval: snoozeInterval,
                minimumReleaseAge: minimumReleaseAge
            ),
            promptStateStore: promptStateStore,
            buildEnvironmentDetector: MockBuildEnvironmentDetector(isProduction: isProduction),
            updateSource: updateSource,
            storefrontResolver: MockStorefrontResolver(),
            currentDate: { currentDate },
            currentOSVersion: { AppVersion(currentOSVersionString) },
            bundleMetadataProvider: { resolvedBundleMetadata },
            overridesThrottle: overridesThrottle
        )
    }

    // MARK: - Gate 1: Throttle

    @Test func withinThrottleWindowIsSuppressed() async throws {
        let store = InMemoryPromptStateStore()
        let lastCheck = self.referenceDate.addingTimeInterval(-3600)  // 1 h ago
        await store.recordLastCheckDate(lastCheck)
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        let nextEligibleDate = lastCheck.addingTimeInterval(self.oneDayInSeconds)
        #expect(outcome == .suppressed(.throttled(nextEligibleDate: nextEligibleDate)))
        #expect(await source.callCount == 0)
    }

    @Test func outsideThrottleWindowContinues() async throws {
        let store = InMemoryPromptStateStore()
        let lastCheck = self.referenceDate.addingTimeInterval(-self.oneDayInSeconds - 1)
        await store.recordLastCheckDate(lastCheck)
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        #expect(
            outcome
                == .updateAvailable(
                    UpdateDescription(
                        installedVersionString: Self.installedVersionString,
                        storeVersionString: Self.storeVersionString,
                        requirement: .optional,
                        metadata: self.makeStoreMetadata()
                    )
                )
        )
        #expect(await source.callCount == 1)
    }

    @Test func throttleOverrideSkipsThrottleGate() async throws {
        let store = InMemoryPromptStateStore()
        let lastCheck = self.referenceDate.addingTimeInterval(-3600)  // within window
        await store.recordLastCheckDate(lastCheck)
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate,
            overridesThrottle: true
        )

        let outcome = try await pipeline.run()

        #expect(await source.callCount == 1)
        guard case .updateAvailable = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
            return
        }
    }

    // MARK: - Gate 2: Production build

    @Test func nonProductionBuildIsSuppressed() async throws {
        let store = InMemoryPromptStateStore()
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            isProduction: false,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        #expect(outcome == .suppressed(.nonProductionBuild))
        #expect(await source.callCount == 0)
    }

    // MARK: - Gate 3: Bundle metadata

    @Test func missingBundleMetadataThrows() async throws {
        let store = InMemoryPromptStateStore()
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let pipeline = UpdateCheckPipeline(
            configuration: UpdateCheckConfiguration(policy: Self.allOptionalPolicy),
            promptStateStore: store,
            buildEnvironmentDetector: MockBuildEnvironmentDetector(isProduction: true),
            updateSource: source,
            storefrontResolver: MockStorefrontResolver(),
            currentDate: { self.referenceDate },
            currentOSVersion: { AppVersion("17.0") },
            bundleMetadataProvider: { nil },
            overridesThrottle: false
        )

        await #expect(throws: UpdateCheckFailure.missingBundleMetadata) {
            try await pipeline.run()
        }
    }

    // MARK: - Gate 4 & 5: Network request and check time recording

    @Test func failedRequestDoesNotRecordCheckTime() async throws {
        let store = InMemoryPromptStateStore()
        let source = MockUpdateSource(result: .failure(.networkUnreachable))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        await #expect(throws: UpdateCheckFailure.networkUnreachable) {
            try await pipeline.run()
        }
        let checkDate = await store.lastCheckDate(currentDate: self.referenceDate)
        #expect(checkDate == nil)
    }

    @Test func successfulRequestRecordsCheckTime() async throws {
        let store = InMemoryPromptStateStore()
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        _ = try await pipeline.run()

        let checkDate = await store.lastCheckDate(currentDate: self.referenceDate)
        #expect(checkDate == self.referenceDate)
    }

    // MARK: - Gate 6: OS compatibility

    @Test func incompatibleStoreVersionIsSuppressed() async throws {
        let store = InMemoryPromptStateStore()
        let metadata = self.makeStoreMetadata(minimumOSVersionString: "19.0")
        let source = MockUpdateSource(result: .success(metadata))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate,
            currentOSVersionString: "17.0"
        )

        let outcome = try await pipeline.run()

        #expect(
            outcome
                == .suppressed(
                    .incompatibleWithDeviceOS(
                        requiredVersion: AppVersion("19.0"),
                        currentVersion: AppVersion("17.0")
                    )
                )
        )
    }

    // MARK: - Gate 7: Release age

    @Test func tooRecentReleaseIsSuppressed() async throws {
        let store = InMemoryPromptStateStore()
        let recentReleaseDate = self.referenceDate.addingTimeInterval(-3600)  // 1 h ago
        let metadata = self.makeStoreMetadata(releaseDate: recentReleaseDate)
        let source = MockUpdateSource(result: .success(metadata))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate,
            minimumReleaseAge: self.oneDayInSeconds
        )

        let outcome = try await pipeline.run()

        #expect(
            outcome
                == .suppressed(
                    .releaseTooRecent(
                        releaseDate: recentReleaseDate,
                        eligibleDate: recentReleaseDate.addingTimeInterval(self.oneDayInSeconds)
                    )
                )
        )
    }

    // MARK: - Gate 8: Version comparison

    @Test func equivalentVersionsAreUpToDate() async throws {
        let store = InMemoryPromptStateStore()
        let metadata = self.makeStoreMetadata(versionString: Self.installedVersionString)
        let source = MockUpdateSource(result: .success(metadata))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        #expect(outcome == .upToDate)
    }

    @Test func installedAheadOfStoreIsInstalledIsNewer() async throws {
        let store = InMemoryPromptStateStore()
        let metadata = self.makeStoreMetadata(versionString: "1.3.0")  // older than installed 1.4.2
        let source = MockUpdateSource(result: .success(metadata))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        #expect(outcome == .installedIsNewer)
    }

    // MARK: - Gate 9: Policy

    @Test func silentPolicyIsSuppressed() async throws {
        let store = InMemoryPromptStateStore()
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let allSilentPolicy = UpdatePolicy(
            major: .silent,
            minor: .silent,
            patch: .silent,
            revision: .silent
        )
        let pipeline = self.makePipeline(
            policy: allSilentPolicy,
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        // 1.4.2 → 1.5.0 is a minor difference
        #expect(outcome == .suppressed(.silentByPolicy(classification: .minor)))
    }

    @Test func requiredPolicyYieldsUpdateAvailableIgnoringSkipAndSnooze() async throws {
        let store = InMemoryPromptStateStore()
        // Snooze and skip are recorded for the store version
        await store.recordSkip(for: Self.storeVersionString)
        await store.recordSnooze(
            for: Self.storeVersionString,
            expiry: self.referenceDate.addingTimeInterval(self.oneDayInSeconds)
        )
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let allRequiredPolicy = UpdatePolicy(
            major: .required,
            minor: .required,
            patch: .required,
            revision: .required
        )
        let pipeline = self.makePipeline(
            policy: allRequiredPolicy,
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        guard case .updateAvailable(let description) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
            return
        }
        #expect(description.requirement == .required)
    }

    // MARK: - Gates 10 & 11: Skip and snooze (optional only)

    @Test func skippedOptionalVersionIsSuppressed() async throws {
        let store = InMemoryPromptStateStore()
        await store.recordSkip(for: Self.storeVersionString)
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        #expect(outcome == .suppressed(.skipped(version: Self.storeVersionString)))
    }

    @Test func snoozedOptionalVersionIsSuppressed() async throws {
        let store = InMemoryPromptStateStore()
        let expiry = self.referenceDate.addingTimeInterval(3600)  // 1 h from now
        await store.recordSnooze(for: Self.storeVersionString, expiry: expiry)
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        #expect(outcome == .suppressed(.snoozed(version: Self.storeVersionString, expiry: expiry)))
    }

    @Test func unsuppressedOptionalVersionYieldsUpdateAvailable() async throws {
        let store = InMemoryPromptStateStore()
        let source = MockUpdateSource(result: .success(self.makeStoreMetadata()))
        let pipeline = self.makePipeline(
            promptStateStore: store,
            updateSource: source,
            currentDate: self.referenceDate
        )

        let outcome = try await pipeline.run()

        #expect(
            outcome
                == .updateAvailable(
                    UpdateDescription(
                        installedVersionString: Self.installedVersionString,
                        storeVersionString: Self.storeVersionString,
                        requirement: .optional,
                        metadata: self.makeStoreMetadata()
                    )
                )
        )
    }
}
