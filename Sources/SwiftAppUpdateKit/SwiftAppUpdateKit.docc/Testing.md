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

// Add a debug button anywhere in your app to present the sheet on demand.
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

``UpdateChecker/checkAtLaunch()`` and ``UpdateChecker/check(shouldBypassThrottle:)`` always return
`.suppressed(.nonProductionBuild)` when running in the Simulator or with a debugger attached.
This is intentional — it prevents a development build from consuming a snooze or skip token,
and from prompting during a UI review session.

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

To exercise the full pipeline on a non-production build — the Simulator, with a debugger attached, or in TestFlight — set `shouldBypassProductionBuildCheck: true` in your configuration:

```swift
let configuration = UpdateCheckConfiguration(
    policy: policy,
    shouldBypassProductionBuildCheck: true  // remove before shipping
)
```

The production-build check is skipped and the pipeline proceeds to the network request. The throttle, compatibility, release age, and policy checks still apply. Do not ship this flag enabled.

## Testing on a Real Device

To exercise the full eleven-gate pipeline, run a device build without an attached debugger.
The production gate passes, and the pipeline proceeds through the remaining ten gates.

Use ``UpdateChecker/check(shouldBypassThrottle:)`` with `shouldBypassThrottle: true` to bypass
the throttle gate and force a network request regardless of when the last check ran:

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

The pipeline still applies every other gate — compatibility, release age, policy, skip, and
snooze — so `.upToDate` or `.suppressed` outcomes are expected unless your installed version
is genuinely behind the store version.
