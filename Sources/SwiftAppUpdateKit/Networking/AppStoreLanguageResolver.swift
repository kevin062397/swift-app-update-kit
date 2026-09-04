//
//  AppStoreLanguageResolver.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 9/3/26.
//

import Foundation

/// Resolves the language parameter used for App Store API requests.
protocol AppStoreLanguageResolver: Sendable {
    func resolveLanguageCode() -> String?
}

struct PreferredAppStoreLanguageResolver: AppStoreLanguageResolver {
    private let strategy: AppStoreLanguageResolutionStrategy

    init(preferredLanguageIdentifiers: @escaping @Sendable () -> [String] = { Locale.preferredLanguages }) {
        self.strategy = AppStoreLanguageResolutionStrategy(
            preferredLanguageIdentifiers: preferredLanguageIdentifiers
        )
    }

    func resolveLanguageCode() -> String? {
        return self.strategy.resolveLanguageCode()
    }
}

struct AppStoreLanguageResolutionStrategy {
    let preferredLanguageIdentifiers: @Sendable () -> [String]

    func resolveLanguageCode() -> String? {
        for identifier in self.preferredLanguageIdentifiers() {
            if let languageCode = Self.languageCode(from: identifier) {
                return languageCode
            }
        }
        return nil
    }

    static func languageCode(from identifier: String) -> String? {
        let languageIdentifierParts =
            identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
        guard
            let languageSubtag = languageIdentifierParts.first?.lowercased(),
            Self.isAlphabetic(languageSubtag)
        else {
            return nil
        }

        for possibleRegionSubtag in languageIdentifierParts.dropFirst() {
            let regionSubtag = possibleRegionSubtag.lowercased()
            if possibleRegionSubtag.count == 2, Self.isAlphabetic(regionSubtag) {
                return "\(languageSubtag)_\(regionSubtag)"
            }
        }
        return nil
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
