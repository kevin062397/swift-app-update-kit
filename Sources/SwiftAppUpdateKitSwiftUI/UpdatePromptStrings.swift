//
//  UpdatePromptStrings.swift
//  SwiftAppUpdateKitSwiftUI
//
//  Created by Haoyuan Xia on 8/27/26.
//

import Foundation

/// The user-visible strings shown on the update prompt.
///
/// Every property has a default drawn from the module's English string catalog.
/// Construct a custom value to override any subset; the remaining properties
/// keep their localized defaults.
///
/// ```swift
/// // Override a single label, keep the rest at their defaults.
/// var strings = UpdatePromptStrings()
/// strings.deferButton = "Remind Me Later"
/// ```
public struct UpdatePromptStrings: Sendable {
    /// The title shown for an optional update.
    public var updateAvailableTitle: String
    /// The title shown for a required update.
    public var updateRequiredTitle: String
    /// The heading above the release notes section.
    public var releaseNotesHeading: String
    /// The label on the primary action button.
    public var updateButton: String
    /// The label on the deferral button (optional updates only).
    public var deferButton: String
    /// The label on the permanent-skip button (optional updates only).
    public var skipButton: String

    /// Creates an update prompt strings value with every property set to its
    /// localized default from the module's string catalog.
    ///
    /// Mutate any property after construction to override it while keeping the
    /// rest at their defaults:
    ///
    /// ```swift
    /// var strings = UpdatePromptStrings()
    /// strings.deferButton = "Remind Me Later"
    /// ```
    public init() {
        self.updateAvailableTitle = String(localized: "updatePrompt.title.updateAvailable", defaultValue: "Update Available", bundle: .module)
        self.updateRequiredTitle = String(localized: "updatePrompt.title.updateRequired", defaultValue: "Update Required", bundle: .module)
        self.releaseNotesHeading = String(localized: "updatePrompt.releaseNotes.heading", defaultValue: "What’s New", bundle: .module)
        self.updateButton = String(localized: "updatePrompt.action.update", defaultValue: "Update Now", bundle: .module)
        self.deferButton = String(localized: "updatePrompt.action.defer", defaultValue: "Update Later", bundle: .module)
        self.skipButton = String(localized: "updatePrompt.action.skip", defaultValue: "Skip This Version", bundle: .module)
    }
}
