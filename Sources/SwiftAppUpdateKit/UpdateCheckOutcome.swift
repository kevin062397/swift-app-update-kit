//
//  UpdateCheckOutcome.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

// MARK: - Failure

enum UpdateCheckFailure: Error, Equatable {
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

enum SuppressionReason: Equatable {
    case nonProductionBuild
    case throttled(nextEligibleDate: Date)
    case incompatibleWithDeviceOS(requiredVersion: AppVersion, currentVersion: AppVersion)
    case releaseTooRecent(releaseDate: Date, eligibleDate: Date)
    case silentByPolicy(classification: VersionClassification)
    case skipped(version: String)
    case snoozed(version: String, expiry: Date)
}

// MARK: - Outcome

enum UpdateCheckOutcome: Equatable {
    case updateAvailable(UpdateDescription)
    case upToDate
    case installedIsNewer
    case suppressed(SuppressionReason)
}

// MARK: - Update description

struct UpdateDescription: Equatable {
    let installedVersionString: String
    let storeVersionString: String
    let requirement: UpdateRequirement
    let metadata: AppStoreMetadata
}
