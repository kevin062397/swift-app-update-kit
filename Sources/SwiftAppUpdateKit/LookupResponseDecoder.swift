//
//  LookupResponseDecoder.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

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
            throw LookupDecodeError.malformedResponse
        }

        guard response.resultCount > 0, let record = response.results.first else {
            throw LookupDecodeError.absentFromStorefront
        }

        guard record.bundleIdentifier == expectedBundleIdentifier else {
            throw LookupDecodeError.identityMismatch
        }

        guard let productPageURL = URL(string: record.trackViewURL) else {
            throw LookupDecodeError.malformedResponse
        }

        // An unparseable release date is treated as arbitrarily old so the release-age gate passes.
        let releaseDate = ISO8601DateFormatter().date(from: record.currentVersionReleaseDate) ?? .distantPast
        let artworkURL = record.artworkURL.flatMap { URL(string: $0) }
        let fileSizeInBytes = record.fileSizeInBytes.flatMap { Int($0) }

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
