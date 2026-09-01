//
//  UpdateCheckerModifierTests.swift
//  SwiftAppUpdateKitSwiftUITests
//
//  Created by Haoyuan Xia on 8/27/26.
//

import Foundation
import Testing

@testable import SwiftAppUpdateKit
@testable import SwiftAppUpdateKitSwiftUI

// MARK: - Mocks

private struct ModifierMockBuildEnvironmentDetector: BuildEnvironmentDetector {
    func isProductionBuild() async -> Bool {
        return true
    }
}

private actor ModifierMockUpdateSource: UpdateSource {
    private let metadata: AppStoreMetadata

    init(metadata: AppStoreMetadata) {
        self.metadata = metadata
    }

    func fetchMetadata(
        bundleIdentifier _: String,
        storefrontCountryCode _: String?
    ) async throws(LookupRequestError) -> AppStoreMetadata {
        return self.metadata
    }
}

private struct ModifierMockStorefrontResolver: StorefrontResolver {
    func resolveStorefrontCountryCode() async -> String? {
        return "US"
    }
}

private struct ModifierMockURLOpener: URLOpener {
    @MainActor
    func open(_: URL) async -> Bool {
        return false
    }
}

// MARK: - Tests

@MainActor
struct UpdateCheckerModifierTests {
    private static let installedVersionString = "1.4.2"
    private static let storeVersionString = "1.5.0"

    private static let allOptionalPolicy = UpdatePolicy(
        major: .optional,
        minor: .optional,
        patch: .optional,
        revision: .optional
    )

    private func makeMetadata(versionString: String = storeVersionString) -> AppStoreMetadata {
        return AppStoreMetadata(
            trackID: 123_456,
            versionString: versionString,
            version: AppVersion(versionString),
            minimumOperatingSystemVersion: AppVersion("17.0"),
            releaseDate: .distantPast,
            productPageURL: URL(string: "https://apps.apple.com/app/id123456")!,
            releaseNotes: nil,
            artworkURL: nil,
            fileSizeInBytes: nil
        )
    }

    private func makeChecker(
        storeVersionString: String = UpdateCheckerModifierTests.storeVersionString
    ) -> UpdateChecker {
        let installedVersionString = Self.installedVersionString
        return UpdateChecker(
            configuration: UpdateCheckConfiguration(policy: Self.allOptionalPolicy),
            promptStateStore: InMemoryPromptStateStore(),
            buildEnvironmentDetector: ModifierMockBuildEnvironmentDetector(),
            updateSource: ModifierMockUpdateSource(metadata: self.makeMetadata(versionString: storeVersionString)),
            storefrontResolver: ModifierMockStorefrontResolver(),
            urlOpener: ModifierMockURLOpener(),
            currentDate: { Date() },
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

    // MARK: - Settle Interval and Claiming

    @Test func updateIsClaimedAfterSettleInterval() async throws {
        let checker = self.makeChecker()
        try await checker.check(shouldBypassThrottle: true)

        let description = await UpdateCheckerModifier.waitAndClaim(
            checker: checker,
            settleInterval: .milliseconds(10)
        )

        #expect(description != nil)
        #expect(checker.presentationState == .presenting)
    }

    @Test func nothingIsClaimedWhenNoPendingUpdateExists() async throws {
        // Store version equals installed version, so no update is found.
        let checker = self.makeChecker(storeVersionString: Self.installedVersionString)
        try await checker.check(shouldBypassThrottle: true)

        let description = await UpdateCheckerModifier.waitAndClaim(
            checker: checker,
            settleInterval: .milliseconds(10)
        )

        #expect(description == nil)
        #expect(!checker.isUpdatePromptReady)
    }

    @Test func cancellationDuringSettleIntervalPreventsClaim() async throws {
        let checker = self.makeChecker()
        try await checker.check(shouldBypassThrottle: true)

        let task = Task<UpdateDescription?, Never> {
            await UpdateCheckerModifier.waitAndClaim(
                checker: checker,
                settleInterval: .seconds(60)
            )
        }
        task.cancel()
        let result = await task.value

        #expect(result == nil)
        // Cancellation leaves the pending update unclaimed.
        #expect(checker.presentationState == .awaitingPermission)
    }

    // MARK: - Permission Gating

    @Test func presentationStateIsAwaitingPermissionWhenPermissionIsWithheld() async throws {
        // When isPermitted = false, the modifier's task guard exits before calling waitAndClaim,
        // leaving the checker in the awaiting-permission state until permission is granted.
        let checker = self.makeChecker()
        try await checker.check(shouldBypassThrottle: true)

        #expect(checker.isUpdatePromptReady)
        #expect(checker.presentationState == .awaitingPermission)
    }

    // MARK: - Ordering

    @Test func updateArrivingBeforePermissionGrantedIsClaimedOncePermitted() async throws {
        // Ordering A: check completes (update available) before permission is granted.
        // The modifier sees isPermitted become true with isUpdatePromptReady already true,
        // starts the task, and claims the update after the settle interval.
        let checker = self.makeChecker()
        try await checker.check(shouldBypassThrottle: true)

        // Simulate the modifier starting its task once permission is granted.
        let description = await UpdateCheckerModifier.waitAndClaim(
            checker: checker,
            settleInterval: .milliseconds(10)
        )

        #expect(description != nil)
        #expect(checker.presentationState == .presenting)
    }

    @Test func permissionGrantedBeforeUpdateArrivesYieldsNothingThenClaimsOnCheckCompletion() async throws {
        // Ordering B: permission is already granted when the modifier runs, but the check has
        // not yet completed. waitAndClaim finds nothing to claim and returns nil. Once the check
        // completes, the modifier's task(id:) re-triggers (shouldAttemptPresentation becomes
        // true) and a new waitAndClaim call succeeds.
        let checker = self.makeChecker()

        // Permission is granted, but no update exists yet.
        let resultBeforeCheck = await UpdateCheckerModifier.waitAndClaim(
            checker: checker,
            settleInterval: .milliseconds(10)
        )
        #expect(resultBeforeCheck == nil)

        // Check completes, update is now pending.
        try await checker.check(shouldBypassThrottle: true)

        // The re-triggered task now claims the update.
        let resultAfterCheck = await UpdateCheckerModifier.waitAndClaim(
            checker: checker,
            settleInterval: .milliseconds(10)
        )
        #expect(resultAfterCheck != nil)
        #expect(checker.presentationState == .presenting)
    }

    // MARK: - Withdrawal and Exclusivity

    @Test func withdrawalReleasesClaimWithoutSuppression() async throws {
        // Simulates the modifier calling releaseUpdatePrompt when isPermitted becomes false
        // while the sheet is showing.
        let checker = self.makeChecker()
        try await checker.check(shouldBypassThrottle: true)

        _ = checker.claimUpdatePrompt()
        checker.releaseUpdatePrompt()

        // Update remains pending; no snooze or skip was recorded.
        #expect(checker.isUpdatePromptReady)
        #expect(checker.presentationState == .awaitingPermission)
    }

    @Test func updateIsClaimableAgainAfterWithdrawal() async throws {
        let checker = self.makeChecker()
        try await checker.check(shouldBypassThrottle: true)

        _ = checker.claimUpdatePrompt()
        checker.releaseUpdatePrompt()

        // Once released, the next waitAndClaim succeeds and re-enters presenting state.
        let description = await UpdateCheckerModifier.waitAndClaim(
            checker: checker,
            settleInterval: .milliseconds(10)
        )
        #expect(description != nil)
        #expect(checker.presentationState == .presenting)
    }

    @Test func secondClaimantFindsNothingWhileFirstIsPresenting() async throws {
        // Exclusivity: a manual presenter alongside the modifier results in only one sheet.
        let checker = self.makeChecker()
        try await checker.check(shouldBypassThrottle: true)

        let firstClaim = checker.claimUpdatePrompt()
        #expect(firstClaim != nil)

        // A second call (from a second modifier or a manual presenter) gets nothing.
        let secondClaim = checker.claimUpdatePrompt()
        #expect(secondClaim == nil)
        #expect(checker.presentationState == .presenting)
    }
}
