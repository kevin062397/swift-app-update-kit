//
//  AppStoreMetadata.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

/// The App Store metadata for a specific version of an app, decoded from the Lookup API response.
public struct AppStoreMetadata: Equatable, Sendable {
    public let trackID: Int
    public let versionString: String
    public let version: AppVersion
    public let minimumOperatingSystemVersion: AppVersion
    public let releaseDate: Date
    public let productPageURL: URL
    public let releaseNotes: String?
    public let artworkURL: URL?
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
