//
//  AppVersionTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/25/26.
//

import Testing

@testable import SwiftAppUpdateKit

struct AppVersionTests {
    // MARK: - Ordering matrix: equivalent pairs

    @Test(
        arguments: zip(
            ["1.2", "1.2.0", "1.2.3", "1.02", "1.2.3-beta"],
            ["1.2.0", "1.2", "1.2.3.0", "1.2", "1.2.3"]
        )
    )
    func equivalentVersions(_ installed: String, _ store: String) {
        let installedVersion = AppVersion(installed)
        let storeVersion = AppVersion(store)
        #expect(installedVersion == storeVersion)
        #expect(!(installedVersion < storeVersion))
        #expect(!(storeVersion < installedVersion))
    }

    // MARK: - Ordering matrix: store ahead

    @Test(
        arguments: zip(
            ["1.9", "1.9.9", "2.0", "1.2.3", "", "abc"],
            ["1.10", "1.10.0", "10.0", "1.2.3.1", "1.0.0", "1.0.0"]
        )
    )
    func storeAhead(_ installed: String, _ store: String) {
        let installedVersion = AppVersion(installed)
        let storeVersion = AppVersion(store)
        #expect(installedVersion < storeVersion)
        #expect(installedVersion != storeVersion)
    }

    // MARK: - Ordering matrix: installed ahead

    @Test func installedAhead() {
        #expect(AppVersion("1.0.0") > AppVersion(""))
    }

    // MARK: - Hash consistency

    @Test(
        arguments: zip(
            ["1.2", "1.2.0", "1.2.3", "1.02", "1.2.3-beta"],
            ["1.2.0", "1.2", "1.2.3.0", "1.2", "1.2.3"]
        )
    )
    func equivalentVersionsHashEqually(_ version1String: String, _ version2String: String) {
        let version1 = AppVersion(version1String)
        let version2 = AppVersion(version2String)
        #expect(version1 == version2)
        #expect(version1.hashValue == version2.hashValue)
    }

    @Test func setDeduplicatesEquivalentVersions() {
        let versions: Set<AppVersion> = [
            AppVersion("1.2"),
            AppVersion("1.2.0"),
            AppVersion("1.2.0.0"),
        ]
        #expect(versions.count == 1)
    }

    // MARK: - Classification

    @Test func classifiesMajorDifference() {
        #expect(AppVersion.classify(AppVersion("1.0.0"), AppVersion("2.0.0")) == .major)
    }

    @Test func classifiesMinorDifference() {
        #expect(AppVersion.classify(AppVersion("1.0.0"), AppVersion("1.1.0")) == .minor)
    }

    @Test func classifiesPatchDifference() {
        #expect(AppVersion.classify(AppVersion("1.0.0"), AppVersion("1.0.1")) == .patch)
    }

    @Test func classifiesRevisionDifference() {
        #expect(AppVersion.classify(AppVersion("1.0.0"), AppVersion("1.0.0.1")) == .revision)
    }

    @Test func classifiesNilForEquivalentVersions() {
        #expect(AppVersion.classify(AppVersion("1.2"), AppVersion("1.2.0")) == nil)
    }
}
