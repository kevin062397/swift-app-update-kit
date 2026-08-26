//
//  StorefrontResolver.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import StoreKit

// MARK: - Protocol

/// Resolves the user's App Store storefront to a two-letter country code
/// suitable for the `country` parameter of the Lookup API.
protocol StorefrontResolver: Sendable {
    /// Returns a two-letter ISO 3166-1 alpha-2 country code, or `nil` when
    /// neither the StoreKit storefront nor the device region can be read.
    func resolveStorefrontCountryCode() async -> String?
}

// MARK: - Resolution strategy

/// The storefront resolution logic with injectable step functions, so every
/// branch of the fallback chain is testable without a real StoreKit session.
struct StorefrontResolutionStrategy {
    /// Returns the alpha-3 storefront code from StoreKit, or `nil`.
    let fetchStorefrontThreeLetterCode: @Sendable () async -> String?
    /// Returns the device's region identifier (typically alpha-2), or `nil`.
    let fetchDeviceRegionCode: @Sendable () -> String?

    func resolve() async -> String? {
        // Step 1: StoreKit storefront — authoritative, but alpha-3.
        if let threeLetterCode = await self.fetchStorefrontThreeLetterCode(),
            let twoLetterCode = StorefrontCountryCodeTable.countryCode(forThreeLetterStorefrontCode: threeLetterCode)
        {
            return twoLetterCode
        }
        // Step 2: Device region — a proxy; differs for users with foreign Apple Accounts.
        if let regionCode = self.fetchDeviceRegionCode(),
            regionCode.count == 2,
            regionCode.allSatisfy({ $0.isASCII && $0.isLetter })
        {
            return regionCode.uppercased()
        }
        // Step 3: No storefront parameter — Apple resolves this to the US storefront.
        return nil
    }
}

// MARK: - Production implementation

/// The production storefront resolver that queries StoreKit and reads the
/// device locale.
struct AppStoreStorefrontResolver: StorefrontResolver {
    func resolveStorefrontCountryCode() async -> String? {
        return await StorefrontResolutionStrategy(
            fetchStorefrontThreeLetterCode: { await Storefront.current?.countryCode },
            fetchDeviceRegionCode: { Locale.current.region?.identifier }
        ).resolve()
    }
}
