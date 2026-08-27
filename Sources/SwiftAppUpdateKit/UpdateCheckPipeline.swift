//
//  UpdateCheckPipeline.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

// MARK: - Bundle metadata

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

struct UpdateCheckConfiguration {
    let policy: UpdatePolicy
    let throttleInterval: TimeInterval
    let snoozeInterval: TimeInterval
    let minimumReleaseAge: TimeInterval

    init(
        policy: UpdatePolicy,
        throttleInterval: TimeInterval = 86400,
        snoozeInterval: TimeInterval = 86400,
        minimumReleaseAge: TimeInterval = 86400
    ) {
        self.policy = policy
        self.throttleInterval = throttleInterval
        self.snoozeInterval = snoozeInterval
        self.minimumReleaseAge = minimumReleaseAge
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
    let overridesThrottle: Bool

    func run() async throws(UpdateCheckFailure) -> UpdateCheckOutcome {
        let now = self.currentDate()

        // Gate 1: Outside throttle window (or throttle overridden).
        // Environment detection moves after this gate because its StoreKit lookup can take up to 3 s
        // on first access; throttled launches — the common case — skip the gate entirely.
        if !self.overridesThrottle {
            if let lastCheck = await self.promptStateStore.lastCheckDate(currentDate: now) {
                let nextEligibleDate = lastCheck.addingTimeInterval(self.configuration.throttleInterval)
                if now < nextEligibleDate {
                    return .suppressed(.throttled(nextEligibleDate: nextEligibleDate))
                }
            }
        }

        // Gate 2: Production build.
        // Placed after the throttle gate so that the StoreKit lookup is skipped on throttled launches.
        if await !self.buildEnvironmentDetector.isProductionBuild() {
            return .suppressed(.nonProductionBuild)
        }

        // Gate 3: Read bundle identifier and installed version.
        guard let bundleMetadata = self.bundleMetadataProvider() else {
            throw .missingBundleMetadata
        }

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

        // Gate 5: Record successful check time.
        // Must run immediately after a successful fetch and never after a failure, so that a single
        // offline launch does not silence checking for a full throttle window.
        await self.promptStateStore.recordLastCheckDate(now)

        // Gate 6: Minimum OS version at most the running OS.
        let runningOS = self.currentOSVersion()
        if storeMetadata.minimumOperatingSystemVersion > runningOS {
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
            return .suppressed(
                .releaseTooRecent(
                    releaseDate: storeMetadata.releaseDate,
                    eligibleDate: eligibleDate
                )
            )
        }

        // Gate 8: Compare versions.
        if bundleMetadata.installedVersion == storeMetadata.version {
            return .upToDate
        }
        if bundleMetadata.installedVersion > storeMetadata.version {
            return .installedIsNewer
        }

        // Gate 9: Classify the difference and resolve through policy.
        let classification = AppVersion.classify(bundleMetadata.installedVersion, storeMetadata.version)!
        let requirement = self.configuration.policy.requirement(for: classification)

        switch requirement {
        case .silent:
            return .suppressed(.silentByPolicy(classification: classification))

        case .required:
            // Gates 10 and 11 do not apply: skip suppression for required updates is what makes
            // the requirement meaningful.
            break

        case .optional:
            // Gate 10: Version not skipped.
            if await self.promptStateStore.isVersionSkipped(storeMetadata.versionString) {
                return .suppressed(.skipped(version: storeMetadata.versionString))
            }

            // Gate 11: Version not snoozed.
            if let expiry = await self.promptStateStore.snoozeExpiry(
                for: storeMetadata.versionString,
                currentDate: now,
                snoozeInterval: self.configuration.snoozeInterval
            ), now < expiry {
                return .suppressed(.snoozed(version: storeMetadata.versionString, expiry: expiry))
            }
        }

        await self.promptStateStore.pruneEntries(olderThan: storeMetadata.version)

        return .updateAvailable(
            UpdateDescription(
                installedVersionString: bundleMetadata.installedVersionString,
                storeVersionString: storeMetadata.versionString,
                requirement: requirement,
                metadata: storeMetadata
            )
        )
    }
}
