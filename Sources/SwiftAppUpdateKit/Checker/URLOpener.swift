//
//  URLOpener.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import OSLog
import UIKit

protocol URLOpener: Sendable {
    @MainActor
    func open(_ url: URL) async -> Bool
}

struct SystemURLOpener: URLOpener {
    @MainActor
    func open(_ url: URL) async -> Bool {
        Logger.urlOpener.debug(
            "[\(Self.self)] \(#function): Opening URL \(url.absoluteString, privacy: .private)"
        )
        let didOpen = await UIApplication.shared.open(url)
        if didOpen {
            Logger.urlOpener.info("[\(Self.self)] \(#function): URL opened successfully")
        } else {
            Logger.urlOpener.warning("[\(Self.self)] \(#function): UIApplication declined to open URL")
        }
        return didOpen
    }
}
