//
//  BuildEnvironmentDetectorTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/26/26.
//

import StoreKit
import Testing

@testable import SwiftAppUpdateKit

struct BuildEnvironmentDetectorTests {
    private func makeStrategy(
        isRunningInSimulator: Bool = false,
        isDebuggerAttached: Bool = false,
        environment: AppStore.Environment = .production,
        environmentLookupFails: Bool = false
    ) -> BuildEnvironmentDetectionStrategy {
        BuildEnvironmentDetectionStrategy(
            isRunningInSimulator: isRunningInSimulator,
            isDebuggerAttached: isDebuggerAttached,
            fetchAppTransactionEnvironment: {
                if environmentLookupFails {
                    throw URLError(.badServerResponse)
                }
                return environment
            }
        )
    }

    @Test func simulatorBuildIsNotProduction() async {
        let strategy = self.makeStrategy(isRunningInSimulator: true)
        #expect(await strategy.isProductionBuild() == false)
    }

    @Test func debuggerAttachedBuildIsNotProduction() async {
        let strategy = self.makeStrategy(isDebuggerAttached: true)
        #expect(await strategy.isProductionBuild() == false)
    }

    @Test func testFlightBuildIsNotProduction() async {
        let strategy = self.makeStrategy(environment: .sandbox)
        #expect(await strategy.isProductionBuild() == false)
    }

    @Test func xcodeBuildIsNotProduction() async {
        let strategy = self.makeStrategy(environment: .xcode)
        #expect(await strategy.isProductionBuild() == false)
    }

    @Test func productionBuildIsProduction() async {
        let strategy = self.makeStrategy(environment: .production)
        #expect(await strategy.isProductionBuild() == true)
    }

    @Test func failedEnvironmentLookupFallsBackToProduction() async {
        let strategy = self.makeStrategy(environmentLookupFails: true)
        #expect(await strategy.isProductionBuild() == true)
    }
}
