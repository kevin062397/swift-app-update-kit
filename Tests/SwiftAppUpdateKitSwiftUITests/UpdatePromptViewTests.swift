//
//  UpdatePromptViewTests.swift
//  SwiftAppUpdateKitSwiftUITests
//
//  Created by Haoyuan Xia on 8/27/26.
//

import Foundation
import SwiftAppUpdateKit
import Testing

@testable import SwiftAppUpdateKitSwiftUI

@MainActor
struct UpdatePromptViewTests {
    // MARK: - Helpers

    private func makeMetadata(
        releaseNotes: String? = "• Fixed a crash",
        fileSizeInBytes: Int? = 44_039_168
    ) -> AppStoreMetadata {
        AppStoreMetadata(
            trackID: 123_456,
            versionString: "1.5.0",
            version: AppVersion("1.5.0"),
            minimumOperatingSystemVersion: AppVersion("17.0"),
            releaseDate: Date(timeIntervalSinceReferenceDate: 0),
            productPageURL: URL(string: "https://apps.apple.com/app/id123456")!,
            releaseNotes: releaseNotes,
            artworkURL: nil,
            fileSizeInBytes: fileSizeInBytes
        )
    }

    private func makeSheet(
        requirement: UpdateRequirement = .optional,
        strings: UpdatePromptStrings = UpdatePromptStrings(),
        releaseNotes: String? = "• Fixed a crash",
        fileSizeInBytes: Int? = 44_039_168,
        explanatoryMessage: String? = nil
    ) -> UpdatePromptView {
        UpdatePromptView(
            description: UpdateDescription(
                installedVersionString: "1.4.2",
                storeVersionString: "1.5.0",
                requirement: requirement,
                metadata: self.makeMetadata(
                    releaseNotes: releaseNotes,
                    fileSizeInBytes: fileSizeInBytes
                )
            ),
            strings: strings,
            explanatoryMessage: explanatoryMessage,
            onUpdateNow: {},
            onLater: {},
            onSkip: {}
        )
    }

    // MARK: - Title

    @Test func titleIsUpdateAvailableForOptionalRequirement() {
        #expect(self.makeSheet(requirement: .optional).titleText == "Update Available")
    }

    @Test func titleIsUpdateAvailableForSilentRequirement() {
        #expect(self.makeSheet(requirement: .silent).titleText == "Update Available")
    }

    @Test func titleIsUpdateRequiredForRequiredRequirement() {
        #expect(self.makeSheet(requirement: .required).titleText == "Update Required")
    }

    // MARK: - Download size

    @Test func formattedFileSizeIsNilWhenAbsent() {
        #expect(self.makeSheet(fileSizeInBytes: nil).formattedFileSize == nil)
    }

    @Test func formattedFileSizeIsNonNilWhenPresent() {
        #expect(self.makeSheet(fileSizeInBytes: 44_039_168).formattedFileSize != nil)
    }

    // MARK: - Release notes

    @Test func releaseNotesTextIsNilWhenAbsent() {
        #expect(self.makeSheet(releaseNotes: nil).releaseNotesText == nil)
    }

    @Test func releaseNotesTextIsNilWhenEmpty() {
        #expect(self.makeSheet(releaseNotes: "").releaseNotesText == nil)
    }

    @Test func releaseNotesTextIsNilWhenOnlyWhitespace() {
        #expect(self.makeSheet(releaseNotes: "   \n  ").releaseNotesText == nil)
    }

    @Test func releaseNotesTextIsNonNilWhenPresent() {
        #expect(self.makeSheet(releaseNotes: "• Fixed a crash").releaseNotesText != nil)
    }

    @Test func releaseNotesTextPreservesContent() {
        let notes = "• Fixed a crash\n• Faster sync"
        #expect(self.makeSheet(releaseNotes: notes).releaseNotesText == notes)
    }

    // MARK: - Custom strings

    @Test func customStringOverridesTitle() {
        var strings = UpdatePromptStrings()
        strings.updateAvailableTitle = "Get the Latest"
        #expect(self.makeSheet(strings: strings).titleText == "Get the Latest")
    }

    @Test func overridingOneStringKeepsOthersAtTheirDefaults() {
        var strings = UpdatePromptStrings()
        strings.updateAvailableTitle = "Get the Latest"
        // The required title should still be the default because only the available title was overridden.
        #expect(self.makeSheet(requirement: .required, strings: strings).titleText == "Update Required")
    }
}
