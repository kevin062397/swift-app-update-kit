//
//  URLOpener.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import UIKit

protocol URLOpener: Sendable {
    @MainActor
    func open(_ url: URL) async -> Bool
}

struct SystemURLOpener: URLOpener {
    @MainActor
    func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url)
    }
}
