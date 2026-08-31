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

    static let buildEnvironmentDetector = Logger(subsystem: Self.subsystem, category: "BuildEnvironmentDetector")
    static let updateChecker = Logger(subsystem: Self.subsystem, category: "UpdateChecker")
    static let updateCheckPipeline = Logger(subsystem: Self.subsystem, category: "UpdateCheckPipeline")
}
