//
//  UpdatePolicy.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/25/26.
//

/// The action the library takes when a version difference is detected.
public enum UpdateRequirement: Sendable, Equatable {
    /// The difference is detected and never shown to the user.
    case silent
    /// The update sheet presents with all three actions.
    case optional
    /// The update sheet presents with the update action only and cannot be dismissed.
    case required
}

/// The mapping from a version classification to its requirement.
///
/// Every classification must be assigned; there is no default policy.
/// An adopting app declares this once and passes it to the checker.
public struct UpdatePolicy: Sendable {
    public let major: UpdateRequirement
    public let minor: UpdateRequirement
    public let patch: UpdateRequirement
    public let revision: UpdateRequirement

    public init(
        major: UpdateRequirement,
        minor: UpdateRequirement,
        patch: UpdateRequirement,
        revision: UpdateRequirement
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.revision = revision
    }

    /// Returns the requirement assigned to the given classification.
    public func requirement(for classification: VersionClassification) -> UpdateRequirement {
        switch classification {
        case .major:
            return self.major
        case .minor:
            return self.minor
        case .patch:
            return self.patch
        case .revision:
            return self.revision
        }
    }
}
