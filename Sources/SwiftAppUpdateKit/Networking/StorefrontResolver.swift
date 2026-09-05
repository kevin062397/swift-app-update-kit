//
//  StorefrontResolver.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import OSLog
import StoreKit

// MARK: - Protocol

/// Resolves the user's App Store storefront to a two-letter country code
/// suitable for the `country` parameter of the Lookup API.
protocol StorefrontResolver: Sendable {
    /// Returns a two-letter ISO 3166-1 alpha-2 country code, or `nil` when
    /// neither the StoreKit storefront nor the device region can be read.
    func resolveStorefrontCountryCode() async -> String?
}

// MARK: - Resolution Strategy

/// The storefront resolution logic with injectable step functions, so every
/// branch of the fallback chain is testable without a real StoreKit session.
struct StorefrontResolutionStrategy {
    /// Returns the alpha-3 storefront code from StoreKit, or `nil`.
    let fetchStorefrontThreeLetterCode: @Sendable () async -> String?
    /// Returns the device's region identifier (typically alpha-2), or `nil`.
    let fetchDeviceRegionCode: @Sendable () -> String?

    func resolve() async -> String? {
        // Step 1: StoreKit storefront — authoritative, but alpha-3.
        if let threeLetterCode = await self.fetchStorefrontThreeLetterCode() {
            if let twoLetterCode = StorefrontCountryCodeTable.countryCode(forThreeLetterStorefrontCode: threeLetterCode)
            {
                Logger.storefrontResolver.debug(
                    "[\(Self.self)] \(#function): Resolved StoreKit storefront \(threeLetterCode, privacy: .public) to \(twoLetterCode, privacy: .public)"
                )
                return twoLetterCode
            }
            Logger.storefrontResolver.warning(
                "[\(Self.self)] \(#function): StoreKit storefront code \(threeLetterCode, privacy: .public) was not found in the country-code table"
            )
        }
        // Step 2: Device region — a proxy; differs for users with foreign Apple Accounts.
        if let regionCode = self.fetchDeviceRegionCode(),
            regionCode.count == 2,
            regionCode.allSatisfy({ $0.isASCII && $0.isLetter })
        {
            Logger.storefrontResolver.info(
                "[\(Self.self)] \(#function): Falling back to device region \(regionCode.uppercased(), privacy: .public)"
            )
            return regionCode.uppercased()
        }
        // Step 3: No storefront parameter — Apple resolves this to the US storefront.
        Logger.storefrontResolver.warning(
            "[\(Self.self)] \(#function): Unable to resolve storefront or device region; lookup will omit country"
        )
        return nil
    }
}

// MARK: - Production Implementation

/// The production storefront resolver that queries StoreKit and reads the
/// device locale.
struct AppStoreStorefrontResolver: StorefrontResolver {
    func resolveStorefrontCountryCode() async -> String? {
        return await StorefrontResolutionStrategy(
            fetchStorefrontThreeLetterCode: { await Storefront.current?.countryCode },
            fetchDeviceRegionCode: { Locale.current.region?.identifier }
        )
        .resolve()
    }
}
