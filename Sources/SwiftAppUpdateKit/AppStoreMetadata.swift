//
//  AppStoreMetadata.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

/// The App Store metadata for a specific version of an app, decoded from the Lookup API response.
struct AppStoreMetadata {
    let trackID: Int
    let version: AppVersion
    let minimumOperatingSystemVersion: AppVersion
    let releaseDate: Date
    let productPageURL: URL
    let releaseNotes: String?
    let artworkURL: URL?
    let fileSizeInBytes: Int?
}
