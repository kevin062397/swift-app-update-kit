//
//  AppStoreMetadata.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

/// The App Store metadata for a specific version of an app, decoded from the Lookup API response.
public struct AppStoreMetadata: Equatable, Sendable {
    /// The numeric App Store identifier for this app.
    public let trackID: Int
    /// The raw version string as returned by the Lookup API, suitable for display.
    public let versionString: String
    /// The parsed version, used for ordering and classification.
    public let version: AppVersion
    /// The minimum iOS version this release requires.
    public let minimumOperatingSystemVersion: AppVersion
    /// The date this version was released on the App Store.
    public let releaseDate: Date
    /// The HTTPS URL of the app's App Store product page.
    public let productPageURL: URL
    /// The release notes for this version, or `nil` if none were provided.
    public let releaseNotes: String?
    /// The URL of the store artwork for this version, or `nil` if unavailable.
    public let artworkURL: URL?
    /// The download size in bytes, or `nil` if the store did not report it.
    public let fileSizeInBytes: Int?

    public init(
        trackID: Int,
        versionString: String,
        version: AppVersion,
        minimumOperatingSystemVersion: AppVersion,
        releaseDate: Date,
        productPageURL: URL,
        releaseNotes: String?,
        artworkURL: URL?,
        fileSizeInBytes: Int?
    ) {
        self.trackID = trackID
        self.versionString = versionString
        self.version = version
        self.minimumOperatingSystemVersion = minimumOperatingSystemVersion
        self.releaseDate = releaseDate
        self.productPageURL = productPageURL
        self.releaseNotes = releaseNotes
        self.artworkURL = artworkURL
        self.fileSizeInBytes = fileSizeInBytes
    }
}
