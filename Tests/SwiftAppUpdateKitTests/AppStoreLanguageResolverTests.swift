//
//  AppStoreLanguageResolverTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 9/3/26.
//

import Testing

@testable import SwiftAppUpdateKit

struct AppStoreLanguageResolverTests {
    @Test func regionLanguageIdentifierUsesLowercaseUnderscoreFormat() {
        let languageCode = AppStoreLanguageResolutionStrategy.languageCode(from: "en-US")

        #expect(languageCode == "en_us")
    }

    @Test func underscoreSeparatedRegionIdentifierIsAccepted() {
        let languageCode = AppStoreLanguageResolutionStrategy.languageCode(from: "fr_CA")

        #expect(languageCode == "fr_ca")
    }

    @Test func scriptSubtagIsSkippedWhenRegionIsPresent() {
        let languageCode = AppStoreLanguageResolutionStrategy.languageCode(from: "zh-Hans-CN")

        #expect(languageCode == "zh_cn")
    }

    @Test func nonChineseScriptSubtagIsSkippedWhenRegionIsPresent() {
        let languageCode = AppStoreLanguageResolutionStrategy.languageCode(from: "sr-Latn-RS")

        #expect(languageCode == "sr_rs")
    }

    @Test func languageWithoutRegionReturnsNil() {
        let languageCode = AppStoreLanguageResolutionStrategy.languageCode(from: "zh-Hant")

        #expect(languageCode == nil)
    }

    @Test func resolverUsesFirstResolvablePreferredLanguage() {
        let strategy = AppStoreLanguageResolutionStrategy(
            preferredLanguageIdentifiers: { ["123", "en-US"] }
        )

        #expect(strategy.resolveLanguageCode() == "en_us")
    }

    @Test func resolverReturnsNilWhenNoPreferredLanguageCanBeResolved() {
        let strategy = AppStoreLanguageResolutionStrategy(
            preferredLanguageIdentifiers: { ["123", "-"] }
        )

        #expect(strategy.resolveLanguageCode() == nil)
    }
}
