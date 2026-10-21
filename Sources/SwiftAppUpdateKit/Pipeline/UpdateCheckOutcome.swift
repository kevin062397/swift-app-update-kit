//
//  UpdateCheckOutcome.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

// MARK: - Failure

/// A failure that prevented an update check from completing.
///
/// Inspect ``UpdateChecker/lastOutcome`` to see the most recent result without catching;
/// catch this type only when calling ``UpdateChecker/check(shouldBypassThrottle:)`` directly.
public enum UpdateCheckFailure: Error, Equatable, Sendable {
    /// The request could not be sent or completed due to a network error.
    case networkUnreachable
    /// The server returned an HTTP status code outside the 2xx range.
    case serverError(statusCode: Int)
    /// The response body did not match the expected shape.
    case malformedResponse
    /// The lookup succeeded but no app matched the bundle identifier in the queried storefront.
    case absentFromStorefront
    /// The response described a different bundle identifier than the one requested.
    case identityMismatch
    /// The app's bundle identifier or installed version string could not be read at runtime.
    case missingBundleMetadata
}

extension LookupRequestError {
    func asUpdateCheckFailure() -> UpdateCheckFailure {
        switch self {
        case .networkUnreachable:
            return .networkUnreachable
        case .serverError(let statusCode):
            return .serverError(statusCode: statusCode)
        case .malformedResponse:
            return .malformedResponse
        case .unsupportedLanguageCode:
            return .malformedResponse
        case .absentFromStorefront:
            return .absentFromStorefront
        case .identityMismatch:
            return .identityMismatch
        }
    }
}

// MARK: - Suppression Reason

/// The reason the pipeline produced a suppressed outcome rather than an update to present.
///
/// Each case carries the data you need to answer why a prompt did not appear.
/// Read ``UpdateChecker/lastOutcome`` and match on `.suppressed` to inspect it.
public enum SuppressionReason: Equatable, Sendable {
    /// The check ran in a development or test build.
    case nonProductionBuild
    /// The configured throttle interval has not elapsed since the last successful check.
    case throttled(nextEligibleDate: Date)
    /// The store version requires a higher OS version than the device is running.
    case incompatibleWithDeviceOS(requiredVersion: AppVersion, currentVersion: AppVersion)
    /// The store version was published too recently to have cleared the minimum release-age gate.
    case releaseTooRecent(releaseDate: Date, eligibleDate: Date)
    /// The configured policy maps this version classification to a silent requirement.
    case silentByPolicy(description: UpdateDescription, classification: VersionClassification)
    /// The user permanently skipped this version.
    case skipped(description: UpdateDescription)
    /// The user snoozed this version and the snooze has not yet expired.
    case snoozed(description: UpdateDescription, expiry: Date)
}

// MARK: - Outcome

/// The result of a completed update check.
///
/// The eleven-gate decision pipeline produces exactly one of these values on every successful
/// check. Read ``UpdateChecker/lastOutcome`` to see the most recent result at any time.
public enum UpdateCheckOutcome: Equatable, Sendable {
    /// An update passed every gate and is ready to present.
    case updatePromptReady(UpdateDescription)
    /// The installed version matches the store version.
    case upToDate
    /// The installed version is newer than the store version.
    case installedIsNewer
    /// A pipeline gate stopped the check without producing an update to present.
    case suppressed(SuppressionReason)
}

// MARK: - Update Description

/// A newer store version detected by the pipeline.
///
/// Appears in ``UpdateCheckOutcome/updatePromptReady(_:)`` when the update is ready to present,
/// and in ``SuppressionReason/silentByPolicy(description:classification:)``,
/// ``SuppressionReason/skipped(description:)``, and ``SuppressionReason/snoozed(description:expiry:)``
/// when the prompt was suppressed.
public struct UpdateDescription: Equatable, Sendable {
    /// The version string of the currently installed app, as read from the bundle.
    public let installedVersionString: String
    /// The version string of the available update, as returned by the store.
    public let storeVersionString: String
    /// The requirement the configured policy assigned to this version difference.
    public let requirement: UpdateRequirement
    /// The App Store metadata for the available version.
    public let metadata: AppStoreMetadata

    public init(
        installedVersionString: String,
        storeVersionString: String,
        requirement: UpdateRequirement,
        metadata: AppStoreMetadata
    ) {
        self.installedVersionString = installedVersionString
        self.storeVersionString = storeVersionString
        self.requirement = requirement
        self.metadata = metadata
    }
}
