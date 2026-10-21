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
        else {
            Logger.updateCheckPipeline.error(
                "[\(Self.self)] \(#function): Bundle identifier or CFBundleShortVersionString missing"
            )
            return nil
        }
        Logger.updateCheckPipeline.debug(
            "[\(Self.self)] \(#function): Read bundle metadata: bundle=\(identifier, privacy: .public), version=\(versionString, privacy: .public)"
        )
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
    /// The minimum elapsed time between automatic checks. Defaults to one day (86400 s).
    public let throttleInterval: TimeInterval
    /// The duration for which a snoozed version is suppressed. Defaults to one day (86400 s).
    public let snoozeInterval: TimeInterval
    /// The minimum age a store release must reach before it is offered. Defaults to one day (86400 s).
    ///
    /// The iTunes Lookup API and the App Store delivery infrastructure are independent systems.
    /// A new release can become queryable via the API before its binary has fully propagated to
    /// the CDN, creating a window during which the update prompt would direct users to a version
    /// not yet downloadable.
    ///
    /// - Important:
    /// A small value increases the risk of directing users to a version not yet available for download.
    public let minimumReleaseAge: TimeInterval
    /// When `true`, the production-build gate is skipped and checks run in development
    /// and test builds. Defaults to `false`.
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
    let appStoreLanguageResolver: any AppStoreLanguageResolver
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
        Logger.updateCheckPipeline.info("[\(Self.self)] \(#function): Gate 1: Checking throttle window")
        if !self.shouldBypassThrottle {
            if let lastCheck = await self.promptStateStore.lastCheckDate(currentDate: now) {
                let nextEligibleDate = lastCheck.addingTimeInterval(self.configuration.throttleInterval)
                if now < nextEligibleDate {
                    Logger.updateCheckPipeline.info(
                        "[\(Self.self)] \(#function): Gate 1 suppressed: Throttled — next check at \(String(describing: nextEligibleDate), privacy: .public)"
                    )
                    return .suppressed(.throttled(nextEligibleDate: nextEligibleDate))
                }
            }
        }
        Logger.updateCheckPipeline.info("[\(Self.self)] \(#function): Gate 1 passed: Throttle window cleared")

        // Gate 2: Production build.
        // Placed after the throttle gate so that the StoreKit lookup is skipped on throttled launches.
        Logger.updateCheckPipeline.info("[\(Self.self)] \(#function): Gate 2: Checking build environment")
        if !self.shouldBypassProductionBuildCheck,
            await self.buildEnvironmentDetector.currentEnvironment() != .production
        {
            Logger.updateCheckPipeline.info("[\(Self.self)] \(#function): Gate 2 suppressed: Non-production build")
            return .suppressed(.nonProductionBuild)
        }
        Logger.updateCheckPipeline.info("[\(Self.self)] \(#function): Gate 2 passed: Production build confirmed")

        // Gate 3: Read bundle identifier and installed version.
        Logger.updateCheckPipeline.info("[\(Self.self)] \(#function): Gate 3: Reading bundle metadata from Info.plist")
        guard let bundleMetadata = self.bundleMetadataProvider() else {
            Logger.updateCheckPipeline.error(
                "[\(Self.self)] \(#function): Gate 3 failed: Bundle identifier or version string missing from Info.plist"
            )
            throw .missingBundleMetadata
        }
        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Gate 3 passed: \(bundleMetadata.bundleIdentifier, privacy: .public) — installed \(bundleMetadata.installedVersionString, privacy: .public)"
        )

        // Gate 4: Request store metadata.
        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Gate 4: Fetching store metadata for \(bundleMetadata.bundleIdentifier, privacy: .public)"
        )
        let storefrontCode = await self.storefrontResolver.resolveStorefrontCountryCode()
        let languageCodes = self.appStoreLanguageResolver.resolveLanguageCodes()
        let storeMetadata: AppStoreMetadata
        do throws(LookupRequestError) {
            storeMetadata = try await self.updateSource.fetchMetadata(
                bundleIdentifier: bundleMetadata.bundleIdentifier,
                storefrontCountryCode: storefrontCode,
                languageCodes: languageCodes
            )
        } catch {
            Logger.updateCheckPipeline.error(
                "[\(Self.self)] \(#function): Gate 4 failed: \(String(describing: error), privacy: .public)"
            )
            throw error.asUpdateCheckFailure()
        }
        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Gate 4 passed: Store version \(storeMetadata.versionString, privacy: .public)"
        )

        // Gate 5: Record successful check time and prune stale suppression state.
        // Must run immediately after a successful fetch and never after a failure, so that a single
        // offline launch does not silence checking for a full throttle window. Pruning happens here
        // so stale version-keyed entries are bounded even when later gates return early.
        Logger.updateCheckPipeline.debug(
            "[\(Self.self)] \(#function): Gate 5: Recording successful check and pruning stale prompt state"
        )
        await self.promptStateStore.recordLastCheckDate(now)
        await self.promptStateStore.pruneEntries(olderThan: storeMetadata.version)

        // Gate 6: Minimum OS version at most the running OS.
        Logger.updateCheckPipeline.info("[\(Self.self)] \(#function): Gate 6: Checking OS compatibility")
        let runningOS = self.currentOSVersion()
        if storeMetadata.minimumOperatingSystemVersion > runningOS {
            Logger.updateCheckPipeline.info(
                "[\(Self.self)] \(#function): Gate 6 suppressed: Store version requires iOS \(String(describing: storeMetadata.minimumOperatingSystemVersion), privacy: .public) — device runs \(String(describing: runningOS), privacy: .public)"
            )
            return .suppressed(
                .incompatibleWithDeviceOS(
                    requiredVersion: storeMetadata.minimumOperatingSystemVersion,
                    currentVersion: runningOS
                )
            )
        }
        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Gate 6 passed: OS compatible — device iOS \(String(describing: runningOS), privacy: .public), store requires iOS \(String(describing: storeMetadata.minimumOperatingSystemVersion), privacy: .public)"
        )

        // Gate 7: Release at least the minimum release age old.
        Logger.updateCheckPipeline.info("[\(Self.self)] \(#function): Gate 7: Checking release age")
        let eligibleDate = storeMetadata.releaseDate.addingTimeInterval(self.configuration.minimumReleaseAge)
        if now < eligibleDate {
            Logger.updateCheckPipeline.info(
                "[\(Self.self)] \(#function): Gate 7 suppressed: Release too recent — eligible at \(String(describing: eligibleDate), privacy: .public)"
            )
            return .suppressed(
                .releaseTooRecent(
                    releaseDate: storeMetadata.releaseDate,
                    eligibleDate: eligibleDate
                )
            )
        }
        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Gate 7 passed: Version released \(String(describing: storeMetadata.releaseDate), privacy: .public)"
        )

        // Gate 8: Compare versions.
        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Gate 8: Comparing versions — installed \(bundleMetadata.installedVersionString, privacy: .public), store \(storeMetadata.versionString, privacy: .public)"
        )
        if bundleMetadata.installedVersion == storeMetadata.version {
            Logger.updateCheckPipeline.info(
                "[\(Self.self)] \(#function): Gate 8 exited: Up to date (\(bundleMetadata.installedVersionString, privacy: .public))"
            )
            return .upToDate
        }
        if bundleMetadata.installedVersion > storeMetadata.version {
            Logger.updateCheckPipeline.info(
                "[\(Self.self)] \(#function): Gate 8 exited: Installed (\(bundleMetadata.installedVersionString, privacy: .public)) is ahead of store (\(storeMetadata.versionString, privacy: .public))"
            )
            return .installedIsNewer
        }

        // Gate 8 cleared: the store has a newer version. Build its full description before the
        // suppression gates so that every downstream outcome can carry it.
        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Gate 8 passed: Store \(storeMetadata.versionString, privacy: .public) is newer"
        )
        let classification = AppVersion.classify(bundleMetadata.installedVersion, storeMetadata.version)!
        let requirement = self.configuration.policy.requirement(for: classification)
        let description = UpdateDescription(
            installedVersionString: bundleMetadata.installedVersionString,
            storeVersionString: storeMetadata.versionString,
            requirement: requirement,
            metadata: storeMetadata
        )

        // Gate 9: Policy requirement.
        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Gate 9: Applying policy for \(String(describing: classification), privacy: .public) update"
        )
        if requirement == .silent {
            Logger.updateCheckPipeline.info(
                "[\(Self.self)] \(#function): Gate 9 suppressed: \(String(describing: classification), privacy: .public) difference is silent by policy — store \(storeMetadata.versionString, privacy: .public)"
            )
            return .suppressed(.silentByPolicy(description: description, classification: classification))
        }
        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Gate 9 passed: \(String(describing: requirement), privacy: .public) requirement for \(String(describing: classification), privacy: .public) update"
        )

        if requirement == .optional {
            // Gate 10: Version not skipped.
            Logger.updateCheckPipeline.info(
                "[\(Self.self)] \(#function): Gate 10: Checking skip state for \(storeMetadata.versionString, privacy: .public)"
            )
            if await self.promptStateStore.isVersionSkipped(storeMetadata.versionString) {
                Logger.updateCheckPipeline.info(
                    "[\(Self.self)] \(#function): Gate 10 suppressed: \(storeMetadata.versionString, privacy: .public) was skipped by user"
                )
                return .suppressed(.skipped(description: description))
            }
            Logger.updateCheckPipeline.info(
                "[\(Self.self)] \(#function): Gate 10 passed: \(storeMetadata.versionString, privacy: .public) not skipped"
            )

            // Gate 11: Version not snoozed.
            Logger.updateCheckPipeline.info(
                "[\(Self.self)] \(#function): Gate 11: Checking snooze state for \(storeMetadata.versionString, privacy: .public)"
            )
            if let expiry = await self.promptStateStore.snoozeExpiry(
                for: storeMetadata.versionString,
                currentDate: now,
                snoozeInterval: self.configuration.snoozeInterval
            ), now < expiry {
                Logger.updateCheckPipeline.info(
                    "[\(Self.self)] \(#function): Gate 11 suppressed: \(storeMetadata.versionString, privacy: .public) is snoozed until \(String(describing: expiry), privacy: .public)"
                )
                return .suppressed(.snoozed(description: description, expiry: expiry))
            }
            Logger.updateCheckPipeline.info(
                "[\(Self.self)] \(#function): Gate 11 passed: \(storeMetadata.versionString, privacy: .public) not snoozed"
            )
        }
        // Gates 10 and 11 do not apply to required updates: the skip/snooze state is what
        // makes the requirement meaningful.

        Logger.updateCheckPipeline.info(
            "[\(Self.self)] \(#function): Update prompt ready: \(bundleMetadata.installedVersionString, privacy: .public) → \(storeMetadata.versionString, privacy: .public) (\(String(describing: requirement), privacy: .public))"
        )
        return .updatePromptReady(description)
    }
}
