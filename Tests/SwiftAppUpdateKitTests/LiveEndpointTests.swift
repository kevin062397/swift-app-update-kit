//
//  LiveEndpointTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/28/26.
//

//  This suite hits the real iTunes Lookup API. It is disabled by default so that
//  the ordinary test run stays offline and deterministic.
//
//  To enable: set SWIFT_APP_UPDATE_KIT_LIVE_TESTS=1 in the environment before
//  running xcodebuild, or in the scheme's Run arguments.

import Foundation
import Testing

@testable import SwiftAppUpdateKit

private let liveTestsEnabled = ProcessInfo.processInfo.environment["SWIFT_APP_UPDATE_KIT_LIVE_TESTS"] == "1"

// The WWDC app, published and maintained by Apple. Chosen for long-term stability.
private let appBundleIdentifier = "developer.apple.wwdc-Release"

@Suite(.enabled(if: liveTestsEnabled))
struct LiveEndpointTests {
    private let source = AppStoreUpdateSource()

    // MARK: - US Storefront

    @Test func usStorefrontResponseCarriesAllContractFields() async throws {
        let metadata = try await self.source.fetchMetadata(
            bundleIdentifier: appBundleIdentifier,
            storefrontCountryCode: "US",
            languageCodes: ["en_us"]
        )
        #expect(metadata.trackID > 0)
        #expect(!metadata.versionString.isEmpty)
        #expect(metadata.productPageURL.scheme == "https")
        #expect(metadata.releaseDate != .distantPast)
        #expect(metadata.artworkURL != nil)
        #expect((metadata.fileSizeInBytes ?? 0) > 0)
    }

    // MARK: - Non-US Storefront

    @Test func nonUsStorefrontLookupReturnsARecord() async throws {
        let metadata = try await self.source.fetchMetadata(
            bundleIdentifier: appBundleIdentifier,
            storefrontCountryCode: "GB",
            languageCodes: ["en_us"]
        )
        #expect(!metadata.versionString.isEmpty)
        #expect(metadata.productPageURL.scheme == "https")
    }
}
