//
//  StorefrontResolverTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Testing

@testable import SwiftAppUpdateKit

struct StorefrontResolverTests {
    // MARK: - Mapping table

    @Test func storefrontCodeUSAMapsToUS() {
        #expect(StorefrontCountryCodeTable.countryCode(forThreeLetterStorefrontCode: "USA") == "US")
    }

    @Test func storefrontCodeGBRMapsToGB() {
        #expect(StorefrontCountryCodeTable.countryCode(forThreeLetterStorefrontCode: "GBR") == "GB")
    }

    @Test func storefrontCodeJPNMapsToJP() {
        #expect(StorefrontCountryCodeTable.countryCode(forThreeLetterStorefrontCode: "JPN") == "JP")
    }

    @Test func storefrontCodeDEUMapsToDE() {
        #expect(StorefrontCountryCodeTable.countryCode(forThreeLetterStorefrontCode: "DEU") == "DE")
    }

    @Test func storefrontCodeTWNMapsToTW() {
        #expect(StorefrontCountryCodeTable.countryCode(forThreeLetterStorefrontCode: "TWN") == "TW")
    }

    @Test func unknownThreeLetterCodeReturnsNilFromTable() {
        #expect(StorefrontCountryCodeTable.countryCode(forThreeLetterStorefrontCode: "XYZ") == nil)
    }

    // MARK: - Fallback chain

    @Test func storefrontCodeResolvedFromStoreKitThreeLetterCode() async {
        let strategy = StorefrontResolutionStrategy(
            fetchStorefrontThreeLetterCode: { "DEU" },
            fetchDeviceRegionCode: { nil }
        )
        let result = await strategy.resolve()
        #expect(result == "DE")
    }

    @Test func deviceRegionUsedWhenStoreKitIsUnavailable() async {
        let strategy = StorefrontResolutionStrategy(
            fetchStorefrontThreeLetterCode: { nil },
            fetchDeviceRegionCode: { "FR" }
        )
        let result = await strategy.resolve()
        #expect(result == "FR")
    }

    @Test func deviceRegionUsedWhenStoreKitCodeIsNotInTable() async {
        let strategy = StorefrontResolutionStrategy(
            fetchStorefrontThreeLetterCode: { "XYZ" },
            fetchDeviceRegionCode: { "AU" }
        )
        let result = await strategy.resolve()
        #expect(result == "AU")
    }

    @Test func nilReturnedWhenBothStoreKitAndDeviceRegionAreUnavailable() async {
        let strategy = StorefrontResolutionStrategy(
            fetchStorefrontThreeLetterCode: { nil },
            fetchDeviceRegionCode: { nil }
        )
        let result = await strategy.resolve()
        #expect(result == nil)
    }

    @Test func numericDeviceRegionCodeIsIgnored() async {
        // Locale identifiers like "419" (Latin America) must not be used as country codes.
        let strategy = StorefrontResolutionStrategy(
            fetchStorefrontThreeLetterCode: { nil },
            fetchDeviceRegionCode: { "419" }
        )
        let result = await strategy.resolve()
        #expect(result == nil)
    }

    @Test func deviceRegionCodeIsUppercased() async {
        let strategy = StorefrontResolutionStrategy(
            fetchStorefrontThreeLetterCode: { nil },
            fetchDeviceRegionCode: { "us" }
        )
        let result = await strategy.resolve()
        #expect(result == "US")
    }

    @Test func storeKitResultTakesPrecedenceOverDeviceRegion() async {
        let strategy = StorefrontResolutionStrategy(
            fetchStorefrontThreeLetterCode: { "JPN" },
            fetchDeviceRegionCode: { "US" }
        )
        let result = await strategy.resolve()
        #expect(result == "JP")
    }
}
