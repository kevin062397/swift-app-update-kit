//
//  UpdateCheckOutcome.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

// MARK: - Failure

public enum UpdateCheckFailure: Error, Equatable, Sendable {
    case networkUnreachable
    case serverError(statusCode: Int)
    case malformedResponse
    case absentFromStorefront
    case identityMismatch
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
        case .absentFromStorefront:
            return .absentFromStorefront
        case .identityMismatch:
            return .identityMismatch
        }
    }
}

// MARK: - Suppression reason

public enum SuppressionReason: Equatable, Sendable {
    case nonProductionBuild
    case throttled(nextEligibleDate: Date)
    case incompatibleWithDeviceOS(requiredVersion: AppVersion, currentVersion: AppVersion)
    case releaseTooRecent(releaseDate: Date, eligibleDate: Date)
    case silentByPolicy(classification: VersionClassification)
    case skipped(version: String)
    case snoozed(version: String, expiry: Date)
}

// MARK: - Outcome

public enum UpdateCheckOutcome: Equatable, Sendable {
    case updateAvailable(UpdateDescription)
    case upToDate
    case installedIsNewer
    case suppressed(SuppressionReason)
}

// MARK: - Update description

public struct UpdateDescription: Equatable, Sendable {
    public let installedVersionString: String
    public let storeVersionString: String
    public let requirement: UpdateRequirement
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
