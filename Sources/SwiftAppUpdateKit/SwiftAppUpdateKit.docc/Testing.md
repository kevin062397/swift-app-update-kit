# Testing Your Integration

Verify the update prompt layout and diagnose why the pipeline suppressed a check.

## Overview

SwiftAppUpdateKit exposes two independent surfaces you can exercise during development:

- **The view** — `UpdatePromptView` is value-in, callbacks-out and can be presented with any data you construct.
- **The pipeline** — `UpdateChecker` exposes `lastOutcome` and `presentationState` so you can inspect exactly what the pipeline decided.

## Testing the View Layout

Instantiate `UpdatePromptView` directly with constructed data. No checker, no network call, and no App Store account needed. The view renders identically regardless of how the data was produced.

```swift
import SwiftAppUpdateKit
import SwiftAppUpdateKitSwiftUI
import SwiftUI

// Add a debug button anywhere in your app to present the update prompt on demand.
struct DebugUpdatePromptButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("Preview Update Prompt") {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            UpdatePromptView(
                description: UpdateDescription(
                    installedVersionString: "1.4.2",
                    storeVersionString: "1.5.0",
                    requirement: .optional,
                    metadata: AppStoreMetadata(
                        trackID: 123_456_789,
                        versionString: "1.5.0",
                        version: AppVersion("1.5.0"),
                        minimumOperatingSystemVersion: AppVersion("17.0"),
                        releaseDate: .distantPast,
                        productPageURL: URL(string: "https://apps.apple.com/app/id123456789")!,
                        releaseNotes: "• Fixed a crash on launch\n• Faster sync",
                        artworkURL: nil,
                        fileSizeInBytes: 44_039_168
                    )
                ),
                onUpdate: { isPresented = false },
                onDefer: { isPresented = false },
                onSkip: { isPresented = false }
            )
        }
    }
}
```

Test both variants by changing `requirement`:

- `.optional` — shows the update, defer, and skip buttons.
- `.required` — shows only the update button and disables swipe-to-dismiss.

Pass an `explanatoryMessage` to test the required-update info row:

```swift
UpdatePromptView(
    description: UpdateDescription(..., requirement: .required, ...),
    explanatoryMessage: "This update is required to continue using the app.",
    onUpdate: { ... },
    onDefer: { ... },
    onSkip: { ... }
)
```

## Understanding the Production Gate

SwiftAppUpdateKit classifies the running app as one of three ``AppBuildEnvironment`` values:

| Environment                         | Applies to                                                                                       |
| ----------------------------------- | ------------------------------------------------------------------------------------------------ |
| ``AppBuildEnvironment/development`` | The Simulator, a debugger-attached process, or an app transaction reported by StoreKit as Xcode. |
| ``AppBuildEnvironment/test``        | A StoreKit sandbox app transaction, including TestFlight.                                        |
| ``AppBuildEnvironment/production``  | An App Store production app transaction.                                                         |

Simulator and debugger detection take precedence over the StoreKit lookup. If StoreKit cannot provide the app transaction environment, classification falls back to ``AppBuildEnvironment/production`` so an unavailable lookup does not disable update checking for App Store users.

Read the current classification asynchronously when your integration needs to label diagnostics or adapt development tooling:

```swift
let environment = await AppBuildEnvironment.current()
```

``UpdateChecker/checkAtLaunch()`` and ``UpdateChecker/check(shouldBypassThrottle:)`` return `.suppressed(.nonProductionBuild)` for both development and test environments. This prevents those builds from consuming a snooze or skip token or presenting the update prompt during testing.

Inspect ``UpdateChecker/lastOutcome`` after a check to confirm what the pipeline returned:

```swift
checker.checkAtLaunch()

// After the check completes:
if case .suppressed(let reason) = checker.lastOutcome {
    print("Suppressed: \(reason)")
    // → Suppressed: nonProductionBuild  (in Simulator or with debugger)
}
```

## Bypassing the Production Gate

To exercise the full pipeline in a development or test environment, set `shouldBypassProductionBuildCheck: true` in your configuration:

```swift
let configuration = UpdateCheckConfiguration(
    policy: policy,
    shouldBypassProductionBuildCheck: true  // remove before shipping
)
```

The production-build check is skipped and the pipeline proceeds to the network request. The throttle, compatibility, release age, and policy checks still apply. Do not ship this flag enabled.

## Testing the Pipeline

An App Store production build proceeds through the full eleven-gate pipeline. During development or TestFlight testing, enable `shouldBypassProductionBuildCheck` to exercise the same remaining gates.

Use ``UpdateChecker/check(shouldBypassThrottle:)`` with `shouldBypassThrottle: true` to bypass the throttle gate and force a network request regardless of when the last check ran:

```swift
Task {
    do {
        let outcome = try await checker.check(shouldBypassThrottle: true)
        print("Outcome: \(outcome)")
    } catch {
        print("Check failed: \(error)")
    }
}
```

The pipeline still applies every other gate — compatibility, release age, policy, skip, and snooze — so `.upToDate` or `.suppressed` outcomes are expected unless your installed version is genuinely behind the store version.

## Reading Console Logs

Every gate logs its entry, pass, and suppression or failure to `OSLog`. Network and StoreKit errors are logged at the `error` level; everything else at `info`. Filter by subsystem in Console.app or `log stream` to see the full decision trace without attaching a debugger:

```
Subsystem: com.swiftappupdatekit
```

Three categories are available for finer filtering:

| Category                   | Covers                                         |
| -------------------------- | ---------------------------------------------- |
| `UpdateCheckPipeline`      | Every gate in the update check run             |
| `UpdateChecker`            | Check outcomes, prompt lifecycle, user actions |
| `BuildEnvironmentDetector` | Build environment detection path               |

This is particularly useful in TestFlight builds, where a debugger cannot be attached.
