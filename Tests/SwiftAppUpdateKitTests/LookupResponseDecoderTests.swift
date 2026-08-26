//
//  LookupResponseDecoderTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import Testing

@testable import SwiftAppUpdateKit

struct LookupResponseDecoderTests {
    private let bundleIdentifier = "com.example.app"

    // MARK: - Fixtures

    private let normalResponseFixture = """
        {
            "resultCount": 1,
            "results": [
                {
                    "trackId": 1234567890,
                    "bundleId": "com.example.app",
                    "version": "1.5.0",
                    "minimumOsVersion": "17.0",
                    "currentVersionReleaseDate": "2026-08-14T07:00:00Z",
                    "trackViewUrl": "https://apps.apple.com/us/app/example-app/id1234567890",
                    "releaseNotes": "Fixed a crash on launch",
                    "artworkUrl512": "https://example.com/artwork.jpg",
                    "fileSizeBytes": "44039168"
                }
            ]
        }
        """

    private let emptyResultSetFixture = """
        {
            "resultCount": 0,
            "results": []
        }
        """

    private let absentReleaseNotesFixture = """
        {
            "resultCount": 1,
            "results": [
                {
                    "trackId": 1234567890,
                    "bundleId": "com.example.app",
                    "version": "1.5.0",
                    "minimumOsVersion": "17.0",
                    "currentVersionReleaseDate": "2026-08-14T07:00:00Z",
                    "trackViewUrl": "https://apps.apple.com/us/app/example-app/id1234567890",
                    "artworkUrl512": "https://example.com/artwork.jpg",
                    "fileSizeBytes": "44039168"
                }
            ]
        }
        """

    private let mismatchedBundleIdentifierFixture = """
        {
            "resultCount": 1,
            "results": [
                {
                    "trackId": 9999999999,
                    "bundleId": "com.different.app",
                    "version": "2.0.0",
                    "minimumOsVersion": "17.0",
                    "currentVersionReleaseDate": "2026-08-14T07:00:00Z",
                    "trackViewUrl": "https://apps.apple.com/us/app/different-app/id9999999999",
                    "fileSizeBytes": "12345"
                }
            ]
        }
        """

    private let truncatedPayloadFixture = """
        {
            "resultCount": 1,
            "results": [
                {
                    "trackId": 1234567890
                }
            ]
        }
        """

    private func data(from jsonString: String) -> Data {
        Data(jsonString.utf8)
    }

    // MARK: - Tests

    @Test func normalResponseDecodesSuccessfully() throws {
        let metadata = try LookupResponseDecoder.decode(
            self.data(from: self.normalResponseFixture),
            expectedBundleIdentifier: self.bundleIdentifier
        )
        #expect(metadata.trackID == 1_234_567_890)
        #expect(metadata.version == AppVersion("1.5.0"))
        #expect(metadata.minimumOperatingSystemVersion == AppVersion("17.0"))
        #expect(metadata.releaseNotes == "Fixed a crash on launch")
        #expect(metadata.artworkURL == URL(string: "https://example.com/artwork.jpg"))
        #expect(metadata.productPageURL == URL(string: "https://apps.apple.com/us/app/example-app/id1234567890"))
    }

    @Test func emptyResultSetReportsAbsentFromStorefront() {
        #expect(throws: LookupDecodeError.absentFromStorefront) {
            try LookupResponseDecoder.decode(
                data(from: emptyResultSetFixture),
                expectedBundleIdentifier: bundleIdentifier
            )
        }
    }

    @Test func absentReleaseNotesDoesNotFailDecodeAndYieldsNil() throws {
        let metadata = try LookupResponseDecoder.decode(
            self.data(from: self.absentReleaseNotesFixture),
            expectedBundleIdentifier: self.bundleIdentifier
        )
        #expect(metadata.releaseNotes == nil)
    }

    @Test func downloadSizeDecodedFromStringOfDigits() throws {
        let metadata = try LookupResponseDecoder.decode(
            self.data(from: self.normalResponseFixture),
            expectedBundleIdentifier: self.bundleIdentifier
        )
        #expect(metadata.fileSizeInBytes == 44_039_168)
    }

    @Test func mismatchedBundleIdentifierReportsIdentityMismatch() {
        #expect(throws: LookupDecodeError.identityMismatch) {
            try LookupResponseDecoder.decode(
                data(from: mismatchedBundleIdentifierFixture),
                expectedBundleIdentifier: bundleIdentifier
            )
        }
    }

    @Test func truncatedPayloadReportsMalformedResponse() {
        #expect(throws: LookupDecodeError.malformedResponse) {
            try LookupResponseDecoder.decode(
                data(from: truncatedPayloadFixture),
                expectedBundleIdentifier: bundleIdentifier
            )
        }
    }
}
