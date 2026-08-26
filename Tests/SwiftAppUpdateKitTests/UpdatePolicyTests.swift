//
//  UpdatePolicyTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/25/26.
//

import Testing

@testable import SwiftAppUpdateKit

struct UpdatePolicyTests {
    // That a policy cannot be constructed without assigning all four classifications is a
    // compile-time guarantee: UpdatePolicy's initializer requires a value for every member.

    @Test func majorClassificationResolvesToItsRequirement() {
        let policy = UpdatePolicy(major: .required, minor: .optional, patch: .optional, revision: .silent)
        #expect(policy.requirement(for: .major) == .required)
    }

    @Test func minorClassificationResolvesToItsRequirement() {
        let policy = UpdatePolicy(major: .optional, minor: .required, patch: .optional, revision: .silent)
        #expect(policy.requirement(for: .minor) == .required)
    }

    @Test func patchClassificationResolvesToItsRequirement() {
        let policy = UpdatePolicy(major: .optional, minor: .optional, patch: .required, revision: .silent)
        #expect(policy.requirement(for: .patch) == .required)
    }

    @Test func revisionClassificationResolvesToItsRequirement() {
        let policy = UpdatePolicy(major: .optional, minor: .optional, patch: .optional, revision: .required)
        #expect(policy.requirement(for: .revision) == .required)
    }

    @Test func eachClassificationResolvesIndependently() {
        let policy = UpdatePolicy(major: .required, minor: .optional, patch: .silent, revision: .silent)
        #expect(policy.requirement(for: .major) == .required)
        #expect(policy.requirement(for: .minor) == .optional)
        #expect(policy.requirement(for: .patch) == .silent)
        #expect(policy.requirement(for: .revision) == .silent)
    }
}
