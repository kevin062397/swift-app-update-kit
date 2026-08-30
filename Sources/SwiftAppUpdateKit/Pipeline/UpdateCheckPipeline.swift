//
//  UpdateCheckPipeline.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import OSLog

// MARK: - Bundle Metadata

struct BundleMetadata {
    let bundleIdentifier: String
    let installedVersionString: String
    let installedVersion: AppVersion

    static func fromBundle(_ bundle: Bundle = .main) -> BundleMetadata? {
        guard
            let identifier = bundle.bundleIdentifier,
            let versionString = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        return BundleMetadata(
            bundleIdentifier: identifier,
            installedVersionString: versionString,
            installedVersion: AppVersion(versionString)
        )
    }
}

// MARK: - Configuration

/// The policy and interval configuration passed to ``UpdateChecker`` at construction.
///
/// All intervals default to one day (86 400 s). Pass custom values to change the check
/// frequency, snooze duration, or the release-age gate.
public struct UpdateCheckConfiguration: Sendable {
    /// The policy that maps each version classification to a requirement.
    public let policy: UpdatePolicy
    /// The minimum elapsed time between automatic checks. Defaults to one day (86 400 s).
    public let throttleInterval: TimeInterval
    /// The duration for which a snoozed version is suppressed. Defaults to one day (86 400 s).
    public let snoozeInterval: TimeInterval
    /// The minimum age a store release must reach before it is offered. Defaults to one day (86 400 s).
    ///
    /// This gate exists to allow time for a phased rollout to propagate before the prompt reaches users.
    public let minimumReleaseAge: TimeInterval
    /// When `true`, the production-build gate is skipped and checks run in the simulator,
    /// under a debugger, and in TestFlight builds. Defaults to `false`.
    ///
    /// Set this to `true` in a development or test configuration to exercise the full pipeline
    /// on a device without a production build. Do not enable in a configuration you ship to users.
    public let shouldBypassProductionBuildCheck: Bool

    /// Creates a configuration value.
    ///
    /// - Parameter policy: The policy that maps version classifications to requirements.
    /// - Parameter throttleInterval: Minimum seconds between automatic checks. Defaults to 86 400.
    /// - Parameter snoozeInterval: Seconds a snoozed version is suppressed. Defaults to 86 400.
    /// - Parameter minimumReleaseAge: Minimum seconds since release before a version is offered. Defaults to 86 400.
    /// - Parameter shouldBypassProductionBuildCheck: When `true`, skips the production-build gate. Defaults to `false`.
    public init(
        policy: UpdatePolicy,
        throttleInterval: TimeInterval = 86400,
        snoozeInterval: TimeInterval = 86400,
        minimumReleaseAge: TimeInterval = 86400,
        shouldBypassProductionBuildCheck: Bool = false
    ) {
        self.policy = policy
        self.throttleInterval = throttleInterval
        self.snoozeInterval = snoozeInterval
        self.minimumReleaseAge = minimumReleaseAge
        self.shouldBypassProductionBuildCheck = shouldBypassProductionBuildCheck
    }
}

// MARK: - Pipeline

struct UpdateCheckPipeline {
    let configuration: UpdateCheckConfiguration
    let promptStateStore: any PromptStateStore
    let buildEnvironmentDetector: any BuildEnvironmentDetector
    let updateSource: any UpdateSource
    let storefrontResolver: any StorefrontResolver
    let currentDate: @Sendable () -> Date
    let currentOSVersion: @Sendable () -> AppVersion
    let bundleMetadataProvider: @Sendable () -> BundleMetadata?
    let shouldBypassThrottle: Bool
    let shouldBypassProductionBuildCheck: Bool

    func run() async throws(UpdateCheckFailure) -> UpdateCheckOutcome {
        let now = self.currentDate()

        // Gate 1: Outside throttle window (or throttle bypassed).
        // Environment detection moves after this gate because its StoreKit lookup can take up to 3 s
        // on first access; throttled launches — the common case — skip the gate entirely.
        if !self.shouldBypassThrottle {
            if let lastCheck = await self.promptStateStore.lastCheckDate(currentDate: now) {
                let nextEligibleDate = lastCheck.addingTimeInterval(self.configuration.throttleInterval)
                if now < nextEligibleDate {
                    pipelineLogger.info("Suppressed: throttled — next check at \(String(describing: nextEligibleDate), privacy: .public)")
                    return .suppressed(.throttled(nextEligibleDate: nextEligibleDate))
                }
            }
        }

        // Gate 2: Production build.
        // Placed after the throttle gate so that the StoreKit lookup is skipped on throttled launches.
        if !self.shouldBypassProductionBuildCheck,
            await !self.buildEnvironmentDetector.isProductionBuild()
        {
            pipelineLogger.info("Suppressed: non-production build")
            return .suppressed(.nonProductionBuild)
        }

        // Gate 3: Read bundle identifier and installed version.
        guard let bundleMetadata = self.bundleMetadataProvider() else {
            throw .missingBundleMetadata
        }
        pipelineLogger.info(
            "Checking \(bundleMetadata.bundleIdentifier, privacy: .public) — installed \(bundleMetadata.installedVersionString, privacy: .public)"
        )

        // Gate 4: Request store metadata.
        let storefrontCode = await self.storefrontResolver.resolveStorefrontCountryCode()
        let storeMetadata: AppStoreMetadata
        do throws(LookupRequestError) {
            storeMetadata = try await self.updateSource.fetchMetadata(
                bundleIdentifier: bundleMetadata.bundleIdentifier,
                storefrontCountryCode: storefrontCode
            )
        } catch {
            throw error.asUpdateCheckFailure()
        }
        pipelineLogger.info("Store version: \(storeMetadata.versionString, privacy: .public)")

        // Gate 5: Record successful check time.
        // Must run immediately after a successful fetch and never after a failure, so that a single
        // offline launch does not silence checking for a full throttle window.
        await self.promptStateStore.recordLastCheckDate(now)

        // Gate 6: Minimum OS version at most the running OS.
        let runningOS = self.currentOSVersion()
        if storeMetadata.minimumOperatingSystemVersion > runningOS {
            pipelineLogger.info(
                "Suppressed: store version requires iOS \(String(describing: storeMetadata.minimumOperatingSystemVersion), privacy: .public) — device runs \(String(describing: runningOS), privacy: .public)"
            )
            return .suppressed(
                .incompatibleWithDeviceOS(
                    requiredVersion: storeMetadata.minimumOperatingSystemVersion,
                    currentVersion: runningOS
                )
            )
        }

        // Gate 7: Release at least the minimum release age old.
        let eligibleDate = storeMetadata.releaseDate.addingTimeInterval(self.configuration.minimumReleaseAge)
        if now < eligibleDate {
            pipelineLogger.info("Suppressed: release too recent — eligible at \(String(describing: eligibleDate), privacy: .public)")
            return .suppressed(
                .releaseTooRecent(
                    releaseDate: storeMetadata.releaseDate,
                    eligibleDate: eligibleDate
                )
            )
        }

        // Gate 8: Compare versions.
        if bundleMetadata.installedVersion == storeMetadata.version {
            pipelineLogger.info("Up to date (\(bundleMetadata.installedVersionString, privacy: .public))")
            return .upToDate
        }
        if bundleMetadata.installedVersion > storeMetadata.version {
            pipelineLogger.info(
                "Installed (\(bundleMetadata.installedVersionString, privacy: .public)) is ahead of store (\(storeMetadata.versionString, privacy: .public))"
            )
            return .installedIsNewer
        }

        // Gate 8 cleared: the store has a newer version. Build its full description before the
        // suppression gates so that every downstream outcome can carry it.
        let classification = AppVersion.classify(bundleMetadata.installedVersion, storeMetadata.version)!
        let requirement = self.configuration.policy.requirement(for: classification)
        let description = UpdateDescription(
            installedVersionString: bundleMetadata.installedVersionString,
            storeVersionString: storeMetadata.versionString,
            requirement: requirement,
            metadata: storeMetadata
        )

        // Gate 9: Policy requirement.
        if requirement == .silent {
            pipelineLogger.info(
                "Suppressed: \(String(describing: classification), privacy: .public) difference is silent by policy — store \(storeMetadata.versionString, privacy: .public)"
            )
            return .suppressed(.silentByPolicy(description: description, classification: classification))
        }

        if requirement == .optional {
            // Gate 10: Version not skipped.
            if await self.promptStateStore.isVersionSkipped(storeMetadata.versionString) {
                pipelineLogger.info("Suppressed: \(storeMetadata.versionString, privacy: .public) was skipped by user")
                return .suppressed(.skipped(description: description))
            }

            // Gate 11: Version not snoozed.
            if let expiry = await self.promptStateStore.snoozeExpiry(
                for: storeMetadata.versionString,
                currentDate: now,
                snoozeInterval: self.configuration.snoozeInterval
            ), now < expiry {
                pipelineLogger.info(
                    "Suppressed: \(storeMetadata.versionString, privacy: .public) is snoozed until \(String(describing: expiry), privacy: .public)"
                )
                return .suppressed(.snoozed(description: description, expiry: expiry))
            }
        }
        // Gates 10 and 11 do not apply to required updates: the skip/snooze state is what
        // makes the requirement meaningful.

        await self.promptStateStore.pruneEntries(olderThan: storeMetadata.version)
        pipelineLogger.info(
            "Update prompt ready: \(bundleMetadata.installedVersionString, privacy: .public) → \(storeMetadata.versionString, privacy: .public) (\(String(describing: requirement), privacy: .public))"
        )
        return .updatePromptReady(description)
    }
}

// MARK: - Logger

private let pipelineLogger = Logger(
    subsystem: "com.swiftappupdatekit",
    category: "UpdateCheckPipeline"
)
