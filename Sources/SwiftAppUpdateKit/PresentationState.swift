//
//  PresentationState.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

/// The state of the pending update with respect to presentation.
///
/// Read ``UpdateChecker/presentationState`` to understand why a prompt has or has not appeared.
/// A value of `.awaitingPermission` that persists means the check found an update but the
/// `isPermitted` condition has not yet become true.
public enum PresentationState: Equatable, Sendable {
    /// No update has passed the pipeline, or the previous one was resolved and no new check
    /// has found a replacement.
    case noPendingUpdate
    /// An update is pending but presentation is not yet permitted.
    case awaitingPermission
    /// A presenter holds the claim and the prompt is on screen.
    case presenting
    /// The user resolved the update by choosing to update, defer, or skip.
    case resolved
}
