//
//  AppVersion.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/25/26.
//

/// An app version parsed from a dotted version string and ordered component-wise as integers.
public struct AppVersion: Sendable {
    private let components: [Int]

    /// Creates a version by parsing the given string.
    public init(_ string: String) {
        self.components =
            string
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { segment in
                let digits = segment.prefix(while: { $0.isNumber && $0.isASCII })
                return Int(digits) ?? 0
            }
    }

    private func component(at index: Int) -> Int {
        return index < self.components.count ? self.components[index] : 0
    }

    private var normalizedComponents: [Int] {
        var result = self.components
        while result.last == 0 {
            result.removeLast()
        }
        return result
    }
}

extension AppVersion: Comparable {
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let leftComponent = lhs.component(at: index)
            let rightComponent = rhs.component(at: index)
            if leftComponent != rightComponent {
                return leftComponent < rightComponent
            }
        }
        return false
    }
}

extension AppVersion: Equatable {
    // Defined in terms of ordering rather than synthesized, so that versions differing only by
    // trailing zero components — e.g. "1.2" vs "1.2.0" — compare equal.
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        return !(lhs < rhs) && !(rhs < lhs)
    }
}

extension AppVersion: Hashable {
    public func hash(into hasher: inout Hasher) {
        // Trailing zeros stripped so that equivalent versions hash identically.
        hasher.combine(self.normalizedComponents)
    }
}

// MARK: - VersionClassification

/// The position of the first differing component between two app versions.
public enum VersionClassification: Sendable, Equatable {
    /// The first component differs.
    case major
    /// The second component differs.
    case minor
    /// The third component differs.
    case patch
    /// The fourth or later component differs.
    case revision
}

extension AppVersion {
    /// Returns the classification of the difference between two versions, or `nil` when equivalent.
    public static func classify(_ version1: AppVersion, _ version2: AppVersion) -> VersionClassification? {
        let count = max(version1.components.count, version2.components.count)
        for index in 0..<count {
            if version1.component(at: index) != version2.component(at: index) {
                switch index {
                case 0:
                    return .major
                case 1:
                    return .minor
                case 2:
                    return .patch
                default:
                    return .revision
                }
            }
        }
        return nil
    }
}
