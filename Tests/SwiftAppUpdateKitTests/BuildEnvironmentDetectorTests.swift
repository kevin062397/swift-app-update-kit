//
//  BuildEnvironmentDetectorTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/26/26.
//

import StoreKit
import Testing

@testable import SwiftAppUpdateKit

private actor EnvironmentLookupCounter {
    private(set) var count = 0

    func increment() {
        self.count += 1
    }
}

struct BuildEnvironmentDetectorTests {
    private func makeStrategy(
        isRunningInSimulator: Bool = false,
        isDebuggerAttached: Bool = false,
        environment: AppStore.Environment = .production,
        environmentLookupFails: Bool = false,
        lookupCounter: EnvironmentLookupCounter? = nil
    ) -> BuildEnvironmentDetectionStrategy {
        BuildEnvironmentDetectionStrategy(
            isRunningInSimulator: isRunningInSimulator,
            isDebuggerAttached: isDebuggerAttached,
            fetchAppTransactionEnvironment: {
                await lookupCounter?.increment()
                if environmentLookupFails {
                    throw URLError(.badServerResponse)
                }
                return environment
            }
        )
    }

    @Test func simulatorBuildIsDevelopmentWithoutEnvironmentLookup() async {
        let lookupCounter = EnvironmentLookupCounter()
        let strategy = self.makeStrategy(isRunningInSimulator: true, lookupCounter: lookupCounter)

        #expect(await strategy.environment() == .development)
        #expect(await lookupCounter.count == 0)
    }

    @Test func debuggerAttachedBuildIsDevelopmentWithoutEnvironmentLookup() async {
        let lookupCounter = EnvironmentLookupCounter()
        let strategy = self.makeStrategy(isDebuggerAttached: true, lookupCounter: lookupCounter)

        #expect(await strategy.environment() == .development)
        #expect(await lookupCounter.count == 0)
    }

    @Test func flightBuildIsTest() async {
        let strategy = self.makeStrategy(environment: .sandbox)
        #expect(await strategy.environment() == .test)
    }

    @Test func xcodeBuildIsDevelopment() async {
        let strategy = self.makeStrategy(environment: .xcode)
        #expect(await strategy.environment() == .development)
    }

    @Test func productionBuildIsProduction() async {
        let strategy = self.makeStrategy(environment: .production)
        #expect(await strategy.environment() == .production)
    }

    @Test func failedEnvironmentLookupFallsBackToProduction() async {
        let strategy = self.makeStrategy(environmentLookupFails: true)
        #expect(await strategy.environment() == .production)
    }
}
