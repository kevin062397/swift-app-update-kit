// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAppUpdateKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftAppUpdateKit",
            targets: ["SwiftAppUpdateKit"]
        ),
        .library(
            name: "SwiftAppUpdateKitSwiftUI",
            targets: ["SwiftAppUpdateKitSwiftUI"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftAppUpdateKit",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "SwiftAppUpdateKitSwiftUI",
            dependencies: ["SwiftAppUpdateKit"],
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "SwiftAppUpdateKitTests",
            dependencies: ["SwiftAppUpdateKit"]
        ),
        .testTarget(
            name: "SwiftAppUpdateKitSwiftUITests",
            dependencies: ["SwiftAppUpdateKit", "SwiftAppUpdateKitSwiftUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
