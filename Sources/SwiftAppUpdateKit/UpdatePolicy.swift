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
    /// The requirement for a major version difference (first component).
    public let major: UpdateRequirement
    /// The requirement for a minor version difference (second component).
    public let minor: UpdateRequirement
    /// The requirement for a patch version difference (third component).
    public let patch: UpdateRequirement
    /// The requirement for a revision difference (fourth component or later).
    public let revision: UpdateRequirement

    /// Creates a policy by assigning a requirement to each version classification.
    ///
    /// - Parameter major: Requirement when the first version component differs.
    /// - Parameter minor: Requirement when the second component differs.
    /// - Parameter patch: Requirement when the third component differs.
    /// - Parameter revision: Requirement when the fourth or later component differs.
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
