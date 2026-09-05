//
//  LookupResponseDecoder.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import OSLog

// MARK: - Decode Error

/// A failure that occurred while decoding an App Store Lookup API response.
enum LookupDecodeError: Error, Equatable {
    /// The response contained no results, meaning the app is not sold in the queried storefront.
    case absentFromStorefront
    /// The response described a different bundle identifier than the one requested.
    case identityMismatch
    /// The response could not be decoded into the expected shape.
    case malformedResponse
}

// MARK: - Internal Decodable Types

private struct LookupResponse: Decodable {
    let resultCount: Int
    let results: [LookupResponseRecord]
}

private struct LookupResponseRecord: Decodable {
    let trackID: Int
    let bundleIdentifier: String
    let version: String
    let minimumOperatingSystemVersion: String
    let currentVersionReleaseDate: String
    let trackViewURL: String
    let releaseNotes: String?
    let artworkURL: String?
    /// Arrives as a string of digits rather than a number; see the Store Metadata Contract.
    let fileSizeInBytes: String?

    private enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case bundleIdentifier = "bundleId"
        case version
        case minimumOperatingSystemVersion = "minimumOsVersion"
        case currentVersionReleaseDate
        case trackViewURL = "trackViewUrl"
        case releaseNotes
        case artworkURL = "artworkUrl512"
        case fileSizeInBytes = "fileSizeBytes"
    }
}

// MARK: - Decoder

enum LookupResponseDecoder {
    static func decode(_ data: Data, expectedBundleIdentifier: String) throws -> AppStoreMetadata {
        let response: LookupResponse
        do {
            response = try JSONDecoder().decode(LookupResponse.self, from: data)
        } catch {
            Logger.lookupResponseDecoder.error(
                "[\(Self.self)] \(#function): Failed to decode lookup response envelope: \(String(describing: error), privacy: .public)"
            )
            throw LookupDecodeError.malformedResponse
        }

        guard response.resultCount > 0, let record = response.results.first else {
            Logger.lookupResponseDecoder.info(
                "[\(Self.self)] \(#function): Lookup response contained no results"
            )
            throw LookupDecodeError.absentFromStorefront
        }

        guard record.bundleIdentifier == expectedBundleIdentifier else {
            Logger.lookupResponseDecoder.error(
                "[\(Self.self)] \(#function): Lookup response bundle mismatch: expected=\(expectedBundleIdentifier, privacy: .public), actual=\(record.bundleIdentifier, privacy: .public)"
            )
            throw LookupDecodeError.identityMismatch
        }

        guard let productPageURL = URL(string: record.trackViewURL) else {
            Logger.lookupResponseDecoder.error(
                "[\(Self.self)] \(#function): Lookup response contained invalid product URL: \(record.trackViewURL, privacy: .private)"
            )
            throw LookupDecodeError.malformedResponse
        }

        // An unparseable release date is treated as arbitrarily old so the release-age gate passes.
        let releaseDate = ISO8601DateFormatter().date(from: record.currentVersionReleaseDate) ?? .distantPast
        if releaseDate == .distantPast {
            Logger.lookupResponseDecoder.warning(
                "[\(Self.self)] \(#function): Lookup response contained unparseable release date \(record.currentVersionReleaseDate, privacy: .public); treating as distant past"
            )
        }
        let artworkURL = record.artworkURL.flatMap { URL(string: $0) }
        let fileSizeInBytes = record.fileSizeInBytes.flatMap { Int($0) }
        if record.artworkURL != nil, artworkURL == nil {
            Logger.lookupResponseDecoder.warning(
                "[\(Self.self)] \(#function): Lookup response contained invalid artwork URL"
            )
        }
        if record.fileSizeInBytes != nil, fileSizeInBytes == nil {
            Logger.lookupResponseDecoder.warning(
                "[\(Self.self)] \(#function): Lookup response contained invalid file size \(record.fileSizeInBytes ?? "", privacy: .public)"
            )
        }
        Logger.lookupResponseDecoder.debug(
            "[\(Self.self)] \(#function): Decoded lookup metadata: trackID=\(record.trackID, privacy: .public), version=\(record.version, privacy: .public)"
        )

        return AppStoreMetadata(
            trackID: record.trackID,
            versionString: record.version,
            version: AppVersion(record.version),
            minimumOperatingSystemVersion: AppVersion(record.minimumOperatingSystemVersion),
            releaseDate: releaseDate,
            productPageURL: productPageURL,
            releaseNotes: record.releaseNotes,
            artworkURL: artworkURL,
            fileSizeInBytes: fileSizeInBytes
        )
    }
}
