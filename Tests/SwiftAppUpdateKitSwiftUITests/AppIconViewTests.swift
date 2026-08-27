//
//  AppIconViewTests.swift
//  SwiftAppUpdateKitSwiftUITests
//
//  Created by Haoyuan Xia on 8/27/26.
//

import Testing
import UIKit

@testable import SwiftAppUpdateKitSwiftUI

struct AppIconViewTests {
    // MARK: - Artwork Loading

    @Test func artworkIsPreferredWhenAvailable() async {
        let resolvedImage = await AppIconView.resolveIcon(
            artworkURL: URL(string: "https://example.com/icon.png")!,
            artworkLoader: { _ in UIImage(systemName: "star.fill") },
            bundleIconLoader: { nil }
        )
        #expect(resolvedImage != nil)
    }

    @Test func artworkLoaderIsNotCalledWhenURLIsAbsent() async {
        actor CallTracker {
            private(set) var wasCalled = false
            func recordCall() {
                self.wasCalled = true
            }
        }
        let tracker = CallTracker()
        _ = await AppIconView.resolveIcon(
            artworkURL: nil,
            artworkLoader: { _ in
                await tracker.recordCall()
                return nil
            },
            bundleIconLoader: { nil }
        )
        await #expect(tracker.wasCalled == false)
    }

    // MARK: - Bundle Icon Fallback

    @Test func bundleIconIsUsedWhenArtworkFails() async {
        let resolvedImage = await AppIconView.resolveIcon(
            artworkURL: URL(string: "https://example.com/icon.png")!,
            artworkLoader: { _ in nil },
            bundleIconLoader: { UIImage(systemName: "app.fill") }
        )
        #expect(resolvedImage != nil)
    }

    @Test func bundleIconIsUsedWhenArtworkURLIsAbsent() async {
        let resolvedImage = await AppIconView.resolveIcon(
            artworkURL: nil,
            artworkLoader: { _ in nil },
            bundleIconLoader: { UIImage(systemName: "app.fill") }
        )
        #expect(resolvedImage != nil)
    }

    // MARK: - Placeholder Fallback

    @Test func resolvedIconIsNilWhenBothSourcesFail() async {
        let resolvedImage = await AppIconView.resolveIcon(
            artworkURL: URL(string: "https://example.com/icon.png")!,
            artworkLoader: { _ in nil },
            bundleIconLoader: { nil }
        )
        #expect(resolvedImage == nil)
    }
}
