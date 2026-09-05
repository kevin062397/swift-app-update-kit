//
//  AppStoreLanguageResolver.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 9/3/26.
//

import Foundation

/// Resolves the language parameter used for App Store API requests.
protocol AppStoreLanguageResolver: Sendable {
    func resolveLanguageCodes() -> [String]
}

struct PreferredAppStoreLanguageResolver: AppStoreLanguageResolver {
    private let strategy: AppStoreLanguageResolutionStrategy

    init(preferredLanguageIdentifiers: @escaping @Sendable () -> [String] = { Locale.preferredLanguages }) {
        self.strategy = AppStoreLanguageResolutionStrategy(
            preferredLanguageIdentifiers: preferredLanguageIdentifiers
        )
    }

    func resolveLanguageCodes() -> [String] {
        return self.strategy.resolveLanguageCodes()
    }
}

struct AppStoreLanguageResolutionStrategy {
    let preferredLanguageIdentifiers: @Sendable () -> [String]

    func resolveLanguageCodes() -> [String] {
        var resolvedLanguageCodes: [String] = []
        var seenLanguageCodes = Set<String>()

        for preferredLanguageIdentifier in self.preferredLanguageIdentifiers() {
            for languageCode in Self.makeLanguageCodes(from: preferredLanguageIdentifier) {
                guard seenLanguageCodes.insert(languageCode).inserted else { continue }
                resolvedLanguageCodes.append(languageCode)
            }
        }

        return resolvedLanguageCodes
    }

    static func makeLanguageCodes(from identifier: String) -> [String] {
        let languageIdentifierParts =
            identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
        guard
            let languageSubtag = languageIdentifierParts.first?.lowercased(),
            languageSubtag.count == 2,
            Self.isAlphabetic(languageSubtag)
        else {
            return []
        }

        let trailingSubtags = languageIdentifierParts.dropFirst().map { $0.lowercased() }
        if languageSubtag == "zh" {
            return Self.makeChineseLanguageCodes(from: trailingSubtags)
        }

        var languageCodes: [String] = []
        if let regionSubtag = Self.findRegionSubtag(from: trailingSubtags) {
            languageCodes.append("\(languageSubtag)_\(regionSubtag)")
        }
        languageCodes.append(languageSubtag)
        return languageCodes
    }

    private static func makeChineseLanguageCodes(from chineseSubtags: [String]) -> [String] {
        // The API's bare "zh" language code resolves to Traditional Chinese, so keep Chinese explicit.
        if chineseSubtags.contains("hans") {
            return ["zh_cn"]
        }
        if chineseSubtags.contains("hant") {
            return chineseSubtags.contains("hk") || chineseSubtags.contains("mo") ? ["zh_hk"] : ["zh_tw"]
        }
        if chineseSubtags.contains("cn") || chineseSubtags.contains("sg") {
            return ["zh_cn"]
        }
        if chineseSubtags.contains("hk") || chineseSubtags.contains("mo") {
            return ["zh_hk"]
        }
        if chineseSubtags.contains("tw") {
            return ["zh_tw"]
        }
        return []
    }

    private static func findRegionSubtag(from trailingSubtags: [String]) -> String? {
        return trailingSubtags.first { subtag in
            subtag.count == 2 && Self.isAlphabetic(subtag)
        }
    }

    private static func isAlphabetic(_ value: String) -> Bool {
        return value.utf8.allSatisfy { byte in
            byte >= CharacterByte.lowercaseA && byte <= CharacterByte.lowercaseZ
        }
    }
}

private enum CharacterByte {
    static let lowercaseA = UInt8(ascii: "a")
    static let lowercaseZ = UInt8(ascii: "z")
}
