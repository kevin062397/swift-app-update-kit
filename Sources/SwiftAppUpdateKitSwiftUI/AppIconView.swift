//
//  AppIconView.swift
//  SwiftAppUpdateKitSwiftUI
//
//  Created by Haoyuan Xia on 8/27/26.
//

import Foundation
import SwiftUI
import UIKit

/// A rounded icon that loads store artwork, falls back to the installed app's bundle icon,
/// and falls back to a neutral placeholder when neither is available.
struct AppIconView: View {
    let artworkURL: URL?

    var artworkLoader: @Sendable (URL) async -> UIImage? = { url in
        await AppIconView.loadArtwork(from: url)
    }

    var bundleIconLoader: @Sendable () -> UIImage? = {
        AppIconView.loadBundleIcon()
    }

    @State private var image: UIImage?

    private let iconDimension: CGFloat = 80.0

    private var iconCornerRadius: CGFloat {
        return self.iconDimension * 0.22
    }

    var body: some View {
        Group {
            if let image = self.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(.systemFill)
            }
        }
        .frame(width: self.iconDimension, height: self.iconDimension)
        .clipShape(RoundedRectangle(cornerRadius: self.iconCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: self.iconCornerRadius)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .task {
            self.image = await Self.resolveIcon(
                artworkURL: self.artworkURL,
                artworkLoader: self.artworkLoader,
                bundleIconLoader: self.bundleIconLoader
            )
        }
    }
}

// MARK: - Loading Helpers (Accessible via @testable Import for Testing)

extension AppIconView {
    /// Resolves the icon by trying the artwork URL first, then the bundle icon, then nil.
    nonisolated static func resolveIcon(
        artworkURL: URL?,
        artworkLoader: @Sendable (URL) async -> UIImage?,
        bundleIconLoader: @Sendable () -> UIImage?
    ) async -> UIImage? {
        if let url = artworkURL, let image = await artworkLoader(url) {
            return image
        }
        return bundleIconLoader()
    }

    /// Downloads and decodes image data from a URL. Returns nil on any failure.
    nonisolated static func loadArtwork(from url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            let image = UIImage(data: data)
        else { return nil }
        return image
    }

    /// Reads the host app's primary icon from its bundle icon file listing.
    nonisolated static func loadBundleIcon() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else { return nil }
        return UIImage(named: iconName)
    }
}

// MARK: - Previews

// Artwork URL sourced from the iTunes Lookup API response for the WWDC app:
// https://itunes.apple.com/lookup?bundleId=developer.apple.wwdc-Release
// Bundle ID taken from: https://support.apple.com/guide/deployment/depece748c41
#Preview("Artwork Loaded") {
    AppIconView(
        artworkURL: URL(
            string:
                "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/f7/db/94/f7db9418-3cfc-81e8-9304-fc13ce9fabe2/AppIcon-Release-0-1x_U007epad-0-0-0-1-0-85-220-0.png/512x512bb.jpg"
        )!,
        artworkLoader: { url in await AppIconView.loadArtwork(from: url) },
        bundleIconLoader: { nil }
    )
}

#Preview("Bundle Icon Fallback") {
    AppIconView(
        artworkURL: nil,
        artworkLoader: { _ in nil },
        bundleIconLoader: AppIconView.loadBundleIcon
    )
}

#Preview("Placeholder Fallback") {
    AppIconView(
        artworkURL: nil,
        artworkLoader: { _ in nil },
        bundleIconLoader: { nil }
    )
}
