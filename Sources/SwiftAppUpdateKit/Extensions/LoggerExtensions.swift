//
//  LoggerExtensions.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/31/26.
//

import Foundation
import OSLog

extension Logger {
    private static let subsystem = "com.swiftappupdatekit"

    static let appStoreLanguageResolver = Logger(subsystem: Self.subsystem, category: "AppStoreLanguageResolver")
    static let appStoreUpdateSource = Logger(subsystem: Self.subsystem, category: "AppStoreUpdateSource")
    static let buildEnvironmentDetector = Logger(subsystem: Self.subsystem, category: "BuildEnvironmentDetector")
    static let lookupResponseDecoder = Logger(subsystem: Self.subsystem, category: "LookupResponseDecoder")
    static let promptStateStore = Logger(subsystem: Self.subsystem, category: "PromptStateStore")
    static let storefrontResolver = Logger(subsystem: Self.subsystem, category: "StorefrontResolver")
    static let updateChecker = Logger(subsystem: Self.subsystem, category: "UpdateChecker")
    static let updateCheckPipeline = Logger(subsystem: Self.subsystem, category: "UpdateCheckPipeline")
    static let urlOpener = Logger(subsystem: Self.subsystem, category: "URLOpener")
}
