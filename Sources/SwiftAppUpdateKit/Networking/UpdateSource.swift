//
//  UpdateSource.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

/// A source that fetches store metadata for a given bundle identifier.
///
/// This is the seam for a future app-hosted update source. The App Store lookup
/// is the only implementation shipping now, but additional sources can be added
/// without changing the pipeline that calls them.
protocol UpdateSource: Sendable {
    func fetchMetadata(
        bundleIdentifier: String,
        storefrontCountryCode: String?,
        languageCode: String?
    ) async throws(LookupRequestError) -> AppStoreMetadata
}
