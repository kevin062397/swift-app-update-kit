//
//  UpdateChecker.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import OSLog
import Observation

/// The observable object that drives the update pipeline, manages the update prompt state, and
/// serializes concurrent check requests.
@MainActor
@Observable
public final class UpdateChecker {
    // MARK: - Observable State

    /// Whether the update prompt is ready to be presented.
    ///
    /// `true` when the most recent check found an update that passed every gate and the user has
    /// not yet snoozed, skipped, or updated. `false` after any of those actions, and also after
    /// a check that confirms the installed version matches or exceeds the store version.
    ///
    /// Use ``availableUpdate`` to retrieve the update description when this is `true`.
    public internal(set) var isUpdatePromptReady: Bool = false

    /// A newer store version detected on the most recent check, if any.
    ///
    /// Set for any outcome in which the store has a newer, compatible, and sufficiently recent
    /// version — including versions the policy classifies as silent, versions the user has snoozed,
    /// and versions the user has skipped. Use it for passive indicators such as a Settings badge
    /// that should reflect store state regardless of prompt suppression.
    ///
    /// Cleared when a check confirms the installed version is current
    /// (``UpdateCheckOutcome/upToDate`` or ``UpdateCheckOutcome/installedIsNewer``).
    /// Left unchanged during throttled checks, failed checks, and non-production-build suppressions.
    public internal(set) var availableUpdate: UpdateDescription?

    /// The outcome of the most recent completed check, for diagnostics.
    public internal(set) var lastOutcome: UpdateCheckOutcome?

    /// The current presentation state of the pending update.
    public internal(set) var presentationState: PresentationState = .noPendingUpdate

    // MARK: - Private State

    // Task<_, any Error> is required because Swift does not provide a Task initializer
    // that produces typed throws; the typed failure is widened to any Error at the call site.
    @ObservationIgnored private var inFlightTask: Task<UpdateCheckOutcome, any Error>?

    // MARK: - Collaborators

    @ObservationIgnored private let configuration: UpdateCheckConfiguration
    @ObservationIgnored private let promptStateStore: any PromptStateStore
    @ObservationIgnored private let buildEnvironmentDetector: any BuildEnvironmentDetector
    @ObservationIgnored private let updateSource: any UpdateSource
    @ObservationIgnored private let storefrontResolver: any StorefrontResolver
    @ObservationIgnored private let urlOpener: any URLOpener
    @ObservationIgnored private let currentDate: @Sendable () -> Date
    @ObservationIgnored private let currentOSVersion: @Sendable () -> AppVersion
    @ObservationIgnored private let bundleMetadataProvider: @Sendable () -> BundleMetadata?

    // MARK: - Initializers

    /// Creates a checker with production collaborators and the given configuration.
    public convenience init(configuration: UpdateCheckConfiguration) {
        let osVersion: @Sendable () -> AppVersion = {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return AppVersion(
                "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            )
        }
        self.init(
            configuration: configuration,
            promptStateStore: UserDefaultsPromptStateStore.make(),
            buildEnvironmentDetector: AppStoreBuildEnvironmentDetector(),
            updateSource: AppStoreUpdateSource(),
            storefrontResolver: AppStoreStorefrontResolver(),
            urlOpener: SystemURLOpener(),
            currentDate: { Date() },
            currentOSVersion: osVersion,
            bundleMetadataProvider: { BundleMetadata.fromBundle() }
        )
    }

    init(
        configuration: UpdateCheckConfiguration,
        promptStateStore: any PromptStateStore,
        buildEnvironmentDetector: any BuildEnvironmentDetector,
        updateSource: any UpdateSource,
        storefrontResolver: any StorefrontResolver,
        urlOpener: any URLOpener,
        currentDate: @escaping @Sendable () -> Date,
        currentOSVersion: @escaping @Sendable () -> AppVersion,
        bundleMetadataProvider: @escaping @Sendable () -> BundleMetadata?
    ) {
        self.configuration = configuration
        self.promptStateStore = promptStateStore
        self.buildEnvironmentDetector = buildEnvironmentDetector
        self.updateSource = updateSource
        self.storefrontResolver = storefrontResolver
        self.urlOpener = urlOpener
        self.currentDate = currentDate
        self.currentOSVersion = currentOSVersion
        self.bundleMetadataProvider = bundleMetadataProvider
    }

    // MARK: - Check Entry Points

    /// Runs a check without exposing failures to the caller, for use at launch.
    ///
    /// Outcomes and failures are both logged. A failure leaves `isUpdatePromptReady`, `availableUpdate`,
    /// and `lastOutcome` unchanged, so the previous values survive a transient error.
    public func checkAtLaunch() {
        Task {
            do {
                let outcome = try await self.check()
                checkerLogger.info(
                    "Update check outcome: \(String(describing: outcome), privacy: .public)"
                )
            } catch {
                checkerLogger.error(
                    "Update check failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Runs a check and returns its outcome, or throws a typed failure.
    ///
    /// If a check is already in flight, the caller joins it and receives its outcome.
    /// No second network request is issued.
    ///
    /// - Parameter shouldBypassThrottle: When `true`, skips the throttle gate so the check
    ///   always performs a network request. Suitable for a user-initiated "Check for Updates"
    ///   action, but does not bypass compatibility or policy gates.
    @discardableResult
    public func check(
        shouldBypassThrottle: Bool = false
    ) async throws(UpdateCheckFailure) -> UpdateCheckOutcome {
        if let existing = self.inFlightTask {
            return try await Self.extractOutcome(from: existing)
        }

        let pipeline = UpdateCheckPipeline(
            configuration: self.configuration,
            promptStateStore: self.promptStateStore,
            buildEnvironmentDetector: self.buildEnvironmentDetector,
            updateSource: self.updateSource,
            storefrontResolver: self.storefrontResolver,
            currentDate: self.currentDate,
            currentOSVersion: self.currentOSVersion,
            bundleMetadataProvider: self.bundleMetadataProvider,
            shouldBypassThrottle: shouldBypassThrottle,
            shouldBypassProductionBuildCheck: self.configuration.shouldBypassProductionBuildCheck
        )

        let task = Task<UpdateCheckOutcome, any Error> {
            try await pipeline.run()
        }
        self.inFlightTask = task
        defer { self.inFlightTask = nil }

        let outcome = try await Self.extractOutcome(from: task)
        self.apply(outcome: outcome)
        return outcome
    }

    // MARK: - Presentation

    /// Claims the update prompt, transitioning to the presenting state.
    ///
    /// Returns the update description if claiming succeeded, or `nil` when
    /// there is no update prompt or another presenter already holds it.
    @discardableResult
    public func claimUpdatePrompt() -> UpdateDescription? {
        guard self.isUpdatePromptReady,
            let description = self.availableUpdate,
            self.presentationState != .presenting
        else { return nil }
        self.presentationState = .presenting
        return description
    }

    /// Releases the update prompt without writing suppression state, as a withdrawal.
    ///
    /// Transitions to awaiting-permission if an update is still pending,
    /// or to nothing-pending if no update remains.
    public func releaseUpdatePrompt() {
        guard self.presentationState == .presenting else { return }
        self.presentationState = self.isUpdatePromptReady ? .awaitingPermission : .noPendingUpdate
    }

    // MARK: - Actions

    /// Opens the App Store product page for the update.
    ///
    /// Tries the `itms-apps://` scheme first, which launches the App Store directly.
    /// Falls back to the HTTPS product page URL from the store metadata when the scheme fails.
    public func updateNow(for description: UpdateDescription) async {
        let appStoreURL = URL(string: "itms-apps://apps.apple.com/app/id\(description.metadata.trackID)")
        if let url = appStoreURL, await self.urlOpener.open(url) {
            return
        }
        if await self.urlOpener.open(description.metadata.productPageURL) {
            return
        }
        checkerLogger.error(
            "Failed to open the App Store for version \(description.storeVersionString, privacy: .public)"
        )
    }

    /// Snoozes the given update for the configured snooze interval, then clears the pending update.
    public func snooze(_ description: UpdateDescription) async {
        let expiry = self.currentDate().addingTimeInterval(self.configuration.snoozeInterval)
        await self.promptStateStore.recordSnooze(for: description.storeVersionString, expiry: expiry)
        self.isUpdatePromptReady = false
        self.presentationState = .resolved
    }

    /// Permanently skips the given update version, then clears the pending update.
    public func skip(_ description: UpdateDescription) async {
        await self.promptStateStore.recordSkip(for: description.storeVersionString)
        self.isUpdatePromptReady = false
        self.presentationState = .resolved
    }

    // MARK: - Private

    private static func extractOutcome(
        from task: Task<UpdateCheckOutcome, any Error>
    ) async throws(UpdateCheckFailure) -> UpdateCheckOutcome {
        do {
            return try await task.value
        } catch let failure as UpdateCheckFailure {
            throw failure
        } catch {
            // UpdateCheckPipeline only throws UpdateCheckFailure; this branch is unreachable.
            preconditionFailure("Unexpected error type from UpdateCheckPipeline: \(error)")
        }
    }

    private func apply(outcome: UpdateCheckOutcome) {
        self.lastOutcome = outcome

        switch outcome {
        case .updatePromptReady(let description):
            // Always update availableUpdate; only re-trigger the presentation cycle for a new version.
            let alreadyPendingThisVersion =
                self.isUpdatePromptReady
                && self.availableUpdate?.storeVersionString == description.storeVersionString
            self.availableUpdate = description
            guard !alreadyPendingThisVersion else { return }
            self.isUpdatePromptReady = true
            // A superseding update during presentation leaves the state as presenting;
            // the sheet observes availableUpdate and handles the withdrawal itself.
            if self.presentationState != .presenting {
                self.presentationState = .awaitingPermission
            }
        case .suppressed(.skipped(description: let description)):
            self.availableUpdate = description
        case .suppressed(.snoozed(description: let description, _)):
            self.availableUpdate = description
        case .suppressed(.silentByPolicy(description: let description, _)):
            // The policy suppressed the prompt, but the store still has a newer version.
            self.availableUpdate = description
            guard self.isUpdatePromptReady else { return }
            self.isUpdatePromptReady = false
            self.presentationState = .noPendingUpdate
        case .upToDate, .installedIsNewer:
            // The store confirms no newer version — clear both the available update and the pending flag.
            self.availableUpdate = nil
            guard self.isUpdatePromptReady else { return }
            self.isUpdatePromptReady = false
            self.presentationState = .noPendingUpdate
        case .suppressed:
            // Early-exit gates (throttle, non-production build, incompatible OS, release too recent):
            // leave all state unchanged.
            break
        }
    }
}

// MARK: - Logger

private let checkerLogger = Logger(
    subsystem: "com.swiftappupdatekit",
    category: "UpdateChecker"
)
