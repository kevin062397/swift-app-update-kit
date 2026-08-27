//
//  UpdatePromptView.swift
//  SwiftAppUpdateKitSwiftUI
//
//  Created by Haoyuan Xia on 8/27/26.
//

import Foundation
import SwiftAppUpdateKit
import SwiftUI

/// The view that presents an available update to the user.
///
/// `UpdatePromptView` is value-in, callbacks-out: it receives the update description
/// and emits the user's choice through one of three callbacks. It reads nothing
/// from its surrounding environment, so it can be presented in any context —
/// as a modal sheet, full-screen cover, in a navigation stack, or embedded in
/// another view — and previewed without a checker.
///
/// The view enforces its own dismissal rules. Both variants disable swipe-to-dismiss;
/// the optional variant offers the "Later" and "Skip This Version" actions as the
/// only paths to dismissal, while the required variant offers only "Update Now".
public struct UpdatePromptView: View {
    private let description: UpdateDescription
    private let strings: UpdatePromptStrings
    private let explanatoryMessage: String?
    private let onUpdateNow: () -> Void
    private let onLater: () -> Void
    private let onSkip: () -> Void

    /// Creates an update prompt view.
    ///
    /// - Parameter description: The update that passed every pipeline gate.
    /// - Parameter strings: The user-visible strings. Defaults to the module's localized catalog values.
    /// - Parameter explanatoryMessage: An optional message shown on required updates only.
    ///   Absent on optional updates regardless of whether a value is provided.
    /// - Parameter onUpdateNow: Called when the user taps "Update Now".
    /// - Parameter onLater: Called when the user taps "Later" (optional updates only).
    /// - Parameter onSkip: Called when the user taps "Skip This Version" (optional updates only).
    public init(
        description: UpdateDescription,
        strings: UpdatePromptStrings = UpdatePromptStrings(),
        explanatoryMessage: String? = nil,
        onUpdateNow: @escaping () -> Void,
        onLater: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.description = description
        self.strings = strings
        self.explanatoryMessage = explanatoryMessage
        self.onUpdateNow = onUpdateNow
        self.onLater = onLater
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: 0.0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30.0) {
                    HStack(alignment: .center, spacing: 15.0) {
                        // App icon placeholder — replaced with real artwork in Step 14.
                        RoundedRectangle(cornerRadius: 22.0)
                            .fill(Color(.placeholderText).opacity(0.5))
                            .frame(width: 80.0, height: 80.0)

                        // Title, version transition, and optional download size.
                        VStack(alignment: .leading) {
                            Text(self.titleText)
                                .font(.title3)
                                .bold()
                                .multilineTextAlignment(.center)
                            (Text(self.description.installedVersionString)
                                + Text(verbatim: " ")
                                + Text(Image(systemName: "arrow.forward"))
                                + Text(verbatim: " ")
                                + Text(self.description.storeVersionString))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .imageScale(.small)
                            if let size = self.formattedFileSize {
                                Text(size)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Explanatory message — required updates only, when provided by the app.
                    if self.description.requirement == .required, let message = self.explanatoryMessage {
                        (Text(Image(systemName: "info.circle"))
                            + Text(verbatim: " ")
                            + Text(message))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Release notes — omitted when absent or empty.
                    if let notes = self.releaseNotesText {
                        VStack(alignment: .leading, spacing: 10.0) {
                            Text(self.strings.releaseNotesHeading)
                                .font(.headline)
                            Text(notes)
                                .font(.body)
                                .lineSpacing(5.0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

            // Actions.
            VStack {
                Button(action: self.onUpdateNow) {
                    Text(self.strings.updateButton)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .prominentButtonStyle()
                .controlSize(.large)
                if self.description.requirement == .optional {
                    Button(action: self.onLater) {
                        Text(self.strings.deferButton)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .standardButtonStyle()
                    .controlSize(.large)
                    Button(action: self.onSkip) {
                        Text(self.strings.skipButton)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .standardButtonStyle()
                    .controlSize(.large)
                }
            }
            .padding(.horizontal)
        }
        .safeAreaPadding()
        .interactiveDismissDisabled()
    }

    // MARK: - Internal Helpers (Accessible via @testable Import for Testing)

    var titleText: String {
        self.description.requirement == .required ? self.strings.updateRequiredTitle : self.strings.updateAvailableTitle
    }

    var formattedFileSize: String? {
        guard let bytes = self.description.metadata.fileSizeInBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var releaseNotesText: String? {
        guard let notes = self.description.metadata.releaseNotes,
            !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return notes
    }
}

// MARK: - Button Style Helpers

extension View {
    @ViewBuilder fileprivate func prominentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder fileprivate func standardButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

// MARK: - Previews

private let previewOptionalMetadata = AppStoreMetadata(
    trackID: 1_234_567_890,
    versionString: "1.5.0",
    version: AppVersion("1.5.0"),
    minimumOperatingSystemVersion: AppVersion("17.0"),
    releaseDate: .distantPast,
    productPageURL: URL(string: "https://apps.apple.com/app/id1234567890")!,
    releaseNotes: "• Fixed a crash on launch for iPad\n• Faster sync",
    artworkURL: nil,
    fileSizeInBytes: 44_039_168
)

private let previewRequiredMetadata = AppStoreMetadata(
    trackID: 1_234_567_890,
    versionString: "2.0.0",
    version: AppVersion("2.0.0"),
    minimumOperatingSystemVersion: AppVersion("17.0"),
    releaseDate: .distantPast,
    productPageURL: URL(string: "https://apps.apple.com/app/id1234567890")!,
    releaseNotes: "• Rebuilt sync engine\n• New icon",
    artworkURL: nil,
    fileSizeInBytes: 51_380_224
)

#Preview("Optional Update") {
    UpdatePromptView(
        description: UpdateDescription(
            installedVersionString: "1.4.2",
            storeVersionString: "1.5.0",
            requirement: .optional,
            metadata: previewOptionalMetadata
        ),
        onUpdateNow: {},
        onLater: {},
        onSkip: {}
    )
}

#Preview("Optional Update — no release notes, no size") {
    UpdatePromptView(
        description: UpdateDescription(
            installedVersionString: "1.4.2",
            storeVersionString: "1.5.0",
            requirement: .optional,
            metadata: AppStoreMetadata(
                trackID: 1_234_567_890,
                versionString: "1.5.0",
                version: AppVersion("1.5.0"),
                minimumOperatingSystemVersion: AppVersion("17.0"),
                releaseDate: .distantPast,
                productPageURL: URL(string: "https://apps.apple.com/app/id1234567890")!,
                releaseNotes: nil,
                artworkURL: nil,
                fileSizeInBytes: nil
            )
        ),
        onUpdateNow: {},
        onLater: {},
        onSkip: {}
    )
}

#Preview("Required Update") {
    UpdatePromptView(
        description: UpdateDescription(
            installedVersionString: "1.4.2",
            storeVersionString: "2.0.0",
            requirement: .required,
            metadata: previewRequiredMetadata
        ),
        explanatoryMessage: "This update contains a required security fix.",
        onUpdateNow: {},
        onLater: {},
        onSkip: {}
    )
}
