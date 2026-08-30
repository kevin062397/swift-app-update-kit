//
//  UpdateCheckerModifier.swift
//  SwiftAppUpdateKitSwiftUI
//
//  Created by Haoyuan Xia on 8/27/26.
//

import Foundation
import SwiftAppUpdateKit
import SwiftUI

// MARK: - Public API

extension View {
    /// Runs a check when this view first appears and presents ``UpdatePromptView`` as a sheet
    /// once an update is available and `isPermitted` is `true`.
    ///
    /// Apply this modifier to the root view of your app:
    ///
    /// ```swift
    /// @main struct MyApp: App {
    ///     @State private var checker = UpdateChecker(configuration: .init())
    ///
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///                 .checkForUpdates(using: checker)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter checker: The checker that drives the update pipeline.
    /// - Parameter isPermitted: Whether presenting the sheet is allowed right now. Re-evaluated
    ///   whenever the surrounding view state changes. Defaults to `true`.
    /// - Parameter settleInterval: Time to wait after both `isPermitted` is `true` and an update
    ///   is available, before the sheet appears. Defaults to one second.
    public func checkForUpdates(
        using checker: UpdateChecker,
        isPermitted: Bool = true,
        settleInterval: Duration = .seconds(1)
    ) -> some View {
        return self.modifier(
            UpdateCheckerModifier(
                checker: checker,
                isPermitted: isPermitted,
                settleInterval: settleInterval
            )
        )
    }
}

// MARK: - Modifier

@MainActor
struct UpdateCheckerModifier: ViewModifier {
    let checker: UpdateChecker
    let isPermitted: Bool
    let settleInterval: Duration

    @State private var hasLaunched = false
    @State private var isSheetPresented = false
    @State private var presentedDescription: UpdateDescription?

    // True when permission is granted, an update is pending, this modifier is not already showing
    // the sheet, and no other presenter holds the claim. Used as the task ID so the task restarts
    // whenever any condition changes — including when another presenter releases the claim.
    private var shouldAttemptPresentation: Bool {
        return self.isPermitted
            && self.checker.isUpdatePromptReady
            && !self.isSheetPresented
            && self.checker.presentationState != .presenting
    }

    func body(content: Content) -> some View {
        return
            content
            .onAppear {
                guard !self.hasLaunched else { return }
                self.hasLaunched = true
                self.checker.checkAtLaunch()
            }
            .sheet(isPresented: self.$isSheetPresented) {
                if let description = self.presentedDescription {
                    UpdatePromptView(
                        description: description,
                        onUpdate: {
                            Task {
                                await self.checker.updateNow(for: description)
                            }
                        },
                        onDefer: {
                            Task {
                                await self.checker.snooze(description)
                            }
                        },
                        onSkip: {
                            Task {
                                await self.checker.skip(description)
                            }
                        }
                    )
                }
            }
            .onChange(of: self.isPermitted) { _, newValue in
                // Revoking permission while the sheet is visible is a withdrawal:
                // release the claim without writing any suppression state.
                if !newValue && self.isSheetPresented {
                    self.checker.releaseUpdatePrompt()
                    self.isSheetPresented = false
                    self.presentedDescription = nil
                }
            }
            .onChange(of: self.checker.isUpdatePromptReady) { _, newIsPending in
                if !newIsPending {
                    // Resolved by a user action (snooze or skip), or the store confirmed no update.
                    self.isSheetPresented = false
                    self.presentedDescription = nil
                }
            }
            .onChange(of: self.checker.availableUpdate) { _, newUpdate in
                // Supersession: a newer update arrived while the sheet is showing the old one.
                // isUpdatePromptReady stays true (no signal), so availableUpdate is the supersession signal.
                if self.isSheetPresented,
                    newUpdate?.storeVersionString != self.presentedDescription?.storeVersionString
                {
                    self.checker.releaseUpdatePrompt()
                    self.isSheetPresented = false
                    self.presentedDescription = nil
                }
            }
            .task(id: self.shouldAttemptPresentation) {
                guard self.shouldAttemptPresentation else { return }
                if let description = await Self.waitAndClaim(
                    checker: self.checker,
                    settleInterval: self.settleInterval
                ) {
                    self.presentedDescription = description
                    self.isSheetPresented = true
                }
            }
    }
}

// MARK: - Presentation Logic (Accessible via @testable Import for Testing)

extension UpdateCheckerModifier {
    /// Waits for the settle interval, then claims the pending update.
    ///
    /// Returns the claimed description, or `nil` if the task was canceled or there is no pending
    /// update (or another presenter already holds the claim).
    @MainActor
    static func waitAndClaim(
        checker: UpdateChecker,
        settleInterval: Duration
    ) async -> UpdateDescription? {
        try? await Task.sleep(for: settleInterval)
        guard !Task.isCancelled else { return nil }
        return checker.claimUpdatePrompt()
    }
}
