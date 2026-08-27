//
//  PresentationState.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

public enum PresentationState: Equatable, Sendable {
    case noPendingUpdate
    case awaitingPermission
    case presenting
    case resolved
}
