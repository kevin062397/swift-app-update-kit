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
}
