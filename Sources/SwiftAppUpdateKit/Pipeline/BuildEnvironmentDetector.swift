//
//  BuildEnvironmentDetector.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import OSLog
import StoreKit

// MARK: - Environment

/// The distribution environment of the running app.
public enum AppBuildEnvironment: Equatable, Sendable {
    /// An App Store production build.
    case production
    /// A sandbox build, including TestFlight.
    case test
    /// A build running from Xcode, in the Simulator, or with a debugger attached.
    case development

    /// Detects the distribution environment of the running app.
    public static func current() async -> AppBuildEnvironment {
        return await AppStoreBuildEnvironmentDetector().currentEnvironment()
    }
}

// MARK: - Protocol

protocol BuildEnvironmentDetector: Sendable {
    func currentEnvironment() async -> AppBuildEnvironment
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

    func environment() async -> AppBuildEnvironment {
        if self.isRunningInSimulator {
            Logger.buildEnvironmentDetector.info("[\(Self.self)] \(#function): Running in Simulator")
            return .development
        }
        if self.isDebuggerAttached {
            Logger.buildEnvironmentDetector.info("[\(Self.self)] \(#function): Debugger attached")
            return .development
        }
        do {
            let environment = try await self.fetchAppTransactionEnvironment()
            Logger.buildEnvironmentDetector.info(
                "[\(Self.self)] \(#function): App transaction environment: \(String(describing: environment), privacy: .public)"
            )
            if environment == .production {
                return .production
            }
            if environment == .xcode {
                return .development
            }
            return .test
        } catch {
            // Fail toward production: disabling checking for all users on a lookup
            // failure would be worse than emitting a redundant prompt in a TestFlight build.
            Logger.buildEnvironmentDetector.error(
                "[\(Self.self)] \(#function): App transaction environment lookup failed: \(String(describing: error), privacy: .public). Treating as a production build."
            )
            return .production
        }
    }
}

// MARK: - Production Implementation

/// The production build environment detector that queries StoreKit's app transaction
/// and inspects the running process for simulator and debugger conditions.
struct AppStoreBuildEnvironmentDetector: BuildEnvironmentDetector {
    func currentEnvironment() async -> AppBuildEnvironment {
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
        )
        .environment()
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
        guard returnCode == 0 else {
            Logger.buildEnvironmentDetector.warning(
                "[\(Self.self)] \(#function): sysctl debugger detection failed with code \(returnCode, privacy: .public); treating debugger as detached"
            )
            return false
        }
        return (kinfo.kp_proc.p_flag & P_TRACED) != 0
    }
}
