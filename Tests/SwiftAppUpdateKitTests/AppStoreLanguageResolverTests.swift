//
//  AppStoreLanguageResolverTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 9/3/26.
//

import Testing

@testable import SwiftAppUpdateKit

struct AppStoreLanguageResolverTests {
    @Test func regionLanguageIdentifierProducesRegionalCandidateBeforeLanguageCandidate() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "en-US")

        #expect(languageCodes == ["en_us", "en"])
    }

    @Test func underscoreSeparatedRegionIdentifierProducesRegionalCandidateBeforeLanguageCandidate() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "fr_CA")

        #expect(languageCodes == ["fr_ca", "fr"])
    }

    @Test func systemRegionCanBeTriedBeforeLanguageFallback() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "fr-US")

        #expect(languageCodes == ["fr_us", "fr"])
    }

    @Test func supportedLanguageWithoutRegionUsesLanguageSubtag() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "fr")

        #expect(languageCodes == ["fr"])
    }

    @Test func scriptSubtagIsSkippedWhenRegionIsPresent() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "zh-Hans-CN")

        #expect(languageCodes == ["zh_cn"])
    }

    @Test func simplifiedChineseScriptUsesChineseAppStoreLanguageCode() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "zh-Hans-US")

        #expect(languageCodes == ["zh_cn"])
    }

    @Test func traditionalChineseScriptUsesTaiwanAppStoreLanguageCode() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "zh-Hant-US")

        #expect(languageCodes == ["zh_tw"])
    }

    @Test func hongKongChineseRegionUsesHongKongAppStoreLanguageCode() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "zh-HK")

        #expect(languageCodes == ["zh_hk"])
    }

    @Test func hongKongTraditionalChineseUsesHongKongAppStoreLanguageCode() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "zh-Hant-HK")

        #expect(languageCodes == ["zh_hk"])
    }

    @Test func macauChineseRegionUsesHongKongAppStoreLanguageCode() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "zh-MO")

        #expect(languageCodes == ["zh_hk"])
    }

    @Test func macauTraditionalChineseUsesHongKongAppStoreLanguageCode() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "zh-Hant-MO")

        #expect(languageCodes == ["zh_hk"])
    }

    @Test func regionalLanguageIdentifierUsesRegionCandidateBeforeLanguageFallback() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "sr-Latn-RS")

        #expect(languageCodes == ["sr_rs", "sr"])
    }

    @Test func languageWithoutRegionUsesLanguageSubtag() {
        let languageCodes = AppStoreLanguageResolutionStrategy.makeLanguageCodes(from: "sr")

        #expect(languageCodes == ["sr"])
    }

    @Test func resolverDeduplicatesLanguageCodesWhilePreservingOrder() {
        let strategy = AppStoreLanguageResolutionStrategy(
            preferredLanguageIdentifiers: { ["123", "fr-US", "fr-CA", "fr"] }
        )

        #expect(strategy.resolveLanguageCodes() == ["fr_us", "fr", "fr_ca"])
    }

    @Test func resolverReturnsEmptyArrayWhenNoPreferredLanguageIdentifierCanBeParsed() {
        let strategy = AppStoreLanguageResolutionStrategy(
            preferredLanguageIdentifiers: { ["123", "-"] }
        )

        #expect(strategy.resolveLanguageCodes().isEmpty)
    }
}
