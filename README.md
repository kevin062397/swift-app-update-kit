# SwiftAppUpdateKit

SwiftAppUpdateKit is a Swift package that detects when a newer version of your app is available on the App Store and prompts the user to update.

## Features

- **Automatic presentation** — one view modifier wires up launch-triggered checks and sheet presentation
- **Eleven-gate decision pipeline** — throttle, build environment, OS compatibility, release age, policy, skip, and snooze gates filter noise before any prompt appears
- **Configurable policy** — map each version classification (major, minor, patch, revision) to silent, optional, or required
- **Optional update** — offers update, defer, and skip actions
- **Required update** — disables dismiss and offers only the update action
- **Customizable strings** — override any subset of the six user-visible labels via manual presentation
- **No third-party dependencies** — built on Foundation and SwiftUI, Swift 6 strict concurrency
- **Privacy manifest included** — `PrivacyInfo.xcprivacy` bundled with the core module

## Requirements

- iOS 17+
- Swift 6

## Installation

Add the dependency in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kevin062397/swift-app-update-kit.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SwiftAppUpdateKitSwiftUI", package: "swift-app-update-kit")
        ]
    )
]
```

Or add it in Xcode via **File → Add Package Dependencies**. Then import the product you need:

| Product                    | Use when                                                       |
| -------------------------- | -------------------------------------------------------------- |
| `SwiftAppUpdateKit`        | You need the checker and pipeline only (no SwiftUI dependency) |
| `SwiftAppUpdateKitSwiftUI` | You want the built-in update sheet and view modifier           |

`SwiftAppUpdateKitSwiftUI` depends on `SwiftAppUpdateKit` automatically.

## Quick Start

### 1. Declare a policy

```swift
import SwiftAppUpdateKit

let policy = UpdatePolicy(
    major: .required,  // must update to continue
    minor: .optional,  // can defer or skip
    patch: .optional,  // can defer or skip
    revision: .silent  // never shown
)

let configuration = UpdateCheckConfiguration(policy: policy)
```

Every classification must be assigned. The right mapping depends on what your version numbers mean to your users — adjust all four to match your release cadence.

### 2. Attach the modifier

```swift
import SwiftAppUpdateKit
import SwiftAppUpdateKitSwiftUI
import SwiftUI

@main
struct MyApp: App {
    @State private var checker = UpdateChecker(configuration: configuration)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .checkForUpdates(using: checker)
        }
    }
}
```

The modifier fires a check on first appearance and presents the update sheet once an update passes every gate.

## Delaying Presentation

Pass `isPermitted` to hold the sheet until a condition becomes true. The check still runs at launch — only the sheet waits.

```swift
.checkForUpdates(using: checker, isPermitted: onboardingComplete)
```

Revoking `isPermitted` while the sheet is visible withdraws it without recording any suppression state, so the same update can be re-presented once permission is re-granted.

## Manual Presentation

Use `checkAtLaunch()` and `claimPendingUpdate()` when you need to slot the sheet into a custom presentation hierarchy, or to pass a custom `UpdatePromptStrings` to override any user-visible label. See [Getting Started](Sources/SwiftAppUpdateKit/SwiftAppUpdateKit.docc/GettingStarted.md) for a complete walkthrough of both.

## Configuration

`UpdateCheckConfiguration` controls three intervals, all defaulting to one day (86 400 s):

| Property            | Purpose                                             |
| ------------------- | --------------------------------------------------- |
| `throttleInterval`  | Minimum time between automatic checks               |
| `snoozeInterval`    | Duration a deferred version is suppressed           |
| `minimumReleaseAge` | Minimum age of a store release before it is offered |

The release age gate allows time for a phased rollout to propagate before the prompt reaches users.

## Testing

The production gate always returns `.suppressed(.nonProductionBuild)` in the Simulator and with a debugger attached, preventing development builds from consuming snooze or skip tokens.

To preview the sheet layout, instantiate `UpdatePromptView` directly with any data you construct — no checker or network call needed. The full DocC article covers both view testing and on-device pipeline testing.

A live endpoint suite exercises the real iTunes Lookup API and is excluded from the default test run to keep it offline and deterministic. To run it, set `SWIFT_APP_UPDATE_KIT_LIVE_TESTS=1` in the environment before running `xcodebuild test`, or in the scheme's Run arguments in Xcode.

## Documentation

Full API reference and getting-started articles are bundled as a DocC catalog. In Xcode, open **Product → Build Documentation** to render them locally.

## License

SwiftAppUpdateKit is available under the MIT License.
