//
//  BuildEnvironmentDetector.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import OSLog
import StoreKit

// MARK: - Protocol

protocol BuildEnvironmentDetector: Sendable {
    func isProductionBuild() async -> Bool
}

// MARK: - Detection Strategy

/// The build environment detection logic with injectable step functions, so every
/// branch is testable without a real StoreKit session or a running debugger.
struct BuildEnvironmentDetectionStrategy {
    let isRunningInSimulator: Bool
    let isDebuggerAttached: Bool
    /// Returns the App Store server environment, or throws when the app transaction
    /// is unavailable.
    let fetchAppTransactionEnvironment: @Sendable () async throws -> AppStore.Environment

    func isProductionBuild() async -> Bool {
        if self.isRunningInSimulator {
            return false
        }
        if self.isDebuggerAttached {
            return false
        }
        do {
            let environment = try await self.fetchAppTransactionEnvironment()
            return environment == .production
        } catch {
            // Fail toward production: disabling checking for all users on a lookup
            // failure would be worse than emitting a redundant prompt in a TestFlight build.
            buildEnvironmentLogger.error(
                "App transaction environment lookup failed: \(String(describing: error), privacy: .public). Treating as a production build."
            )
            return true
        }
    }
}

// MARK: - Production Implementation

/// The production build environment detector that queries StoreKit's app transaction
/// and inspects the running process for simulator and debugger conditions.
struct AppStoreBuildEnvironmentDetector: BuildEnvironmentDetector {
    func isProductionBuild() async -> Bool {
        return await BuildEnvironmentDetectionStrategy(
            isRunningInSimulator: Self.isRunningInSimulator,
            isDebuggerAttached: Self.isDebuggerCurrentlyAttached(),
            fetchAppTransactionEnvironment: {
                let result = try await AppTransaction.shared
                switch result {
                case .verified(let transaction):
                    return transaction.environment
                case .unverified(let transaction, _):
                    return transaction.environment
                }
            }
        ).isProductionBuild()
    }

    private static var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
            return true
        #else
            return false
        #endif
    }

    private static func isDebuggerCurrentlyAttached() -> Bool {
        var kinfo = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let returnCode = sysctl(&mib, UInt32(mib.count), &kinfo, &size, nil, 0)
        guard returnCode == 0 else { return false }
        return (kinfo.kp_proc.p_flag & P_TRACED) != 0
    }
}

// MARK: - Logger

private let buildEnvironmentLogger = Logger(
    subsystem: "com.swiftappupdatekit",
    category: "BuildEnvironmentDetector"
)
