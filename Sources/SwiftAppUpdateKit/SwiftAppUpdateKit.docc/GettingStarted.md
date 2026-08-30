# Getting Started

Add automatic update prompts to your app in a few lines of code.

## Overview

SwiftAppUpdateKit offers two ways to integrate update prompts:

- **Automatic presentation** — attach the `.checkForUpdates(using:)` view modifier (from the `SwiftAppUpdateKitSwiftUI` product) to your root view and the library handles the rest.
- **Manual presentation** — call ``UpdateChecker/checkAtLaunch()`` yourself and present `UpdatePromptView` on your own schedule.

**The deciding question:** if the `isPermitted` condition on the automatic modifier already covers your case — for example, "don't show until onboarding is complete" — use the automatic path. Reach for manual presentation only when you need to slot the update prompt into a presentation hierarchy or navigation flow that the modifier cannot express.

## Declare a Policy

``UpdateCheckConfiguration`` requires an ``UpdatePolicy``. The policy maps each version classification to a requirement, and there is no default — the right mapping depends entirely on what your version numbers mean to your users.

The following policy is one example. It is not a recommendation; treat it as a starting point and adjust every assignment to match your app's release cadence and the expectations it sets with users.

```swift
let policy = UpdatePolicy(
    major: .required,   // Breaking changes: the user must update to continue.
    minor: .optional,   // New features: the user can defer or skip.
    patch: .optional,   // Bug fixes: the user can defer or skip.
    revision: .silent   // Internal or build-number bumps: never shown.
)

let configuration = UpdateCheckConfiguration(policy: policy)
```

## Automatic Presentation

Attach `.checkForUpdates(using:)` to your root view. The library fires a check on first appearance and presents the update prompt once an update is available.

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

### Delaying Presentation

Pass `isPermitted` to delay presentation until a condition you supply becomes true. The check still runs at launch — only the update prompt waits.

```swift
@main
struct MyApp: App {
    @State private var checker = UpdateChecker(configuration: configuration)
    @State private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            ContentView(onboardingComplete: $onboardingComplete)
                .checkForUpdates(using: checker, isPermitted: onboardingComplete)
        }
    }
}
```

Revoking `isPermitted` while the update prompt is visible withdraws it without recording any suppression state, so the same update can be re-presented once permission is re-granted.

## Manual Presentation

Use ``UpdateChecker/checkAtLaunch()`` and ``UpdateChecker/claimUpdatePrompt()`` to manage the update prompt yourself. This path gives you full control over where and when the prompt appears.

```swift
@main
struct MyApp: App {
    @State private var checker = UpdateChecker(configuration: configuration)
    @State private var isSheetPresented = false
    @State private var presentedDescription: UpdateDescription?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { checker.checkAtLaunch() }
                .sheet(isPresented: $isSheetPresented) {
                    if let description = presentedDescription {
                        UpdatePromptView(
                            description: description,
                            onUpdate: { Task { await checker.updateNow(for: description) } },
                            onDefer: { Task { await checker.snooze(description) } },
                            onSkip: { Task { await checker.skip(description) } }
                        )
                    }
                }
                .onChange(of: checker.isUpdatePromptReady) { _, isReady in
                    if isReady, let description = checker.claimUpdatePrompt() {
                        presentedDescription = description
                        isSheetPresented = true
                    } else if !isReady {
                        isSheetPresented = false
                        presentedDescription = nil
                    }
                }
        }
    }
}
```

### Customizing Labels

Pass a custom ``UpdatePromptStrings`` to override any subset of the six user-visible labels. Every property defaults to the localized value from the module's string catalog.

```swift
var strings = UpdatePromptStrings()
strings.deferButton = "Remind Me Later"
strings.skipButton  = "Not Now"

UpdatePromptView(
    description: description,
    strings: strings,
    onUpdate: { Task { await checker.updateNow(for: description) } },
    onDefer: { Task { await checker.snooze(description) } },
    onSkip: { Task { await checker.skip(description) } }
)
```

## Available Update

``UpdateChecker/availableUpdate`` reports the current store update independently of whether the user has snoozed or skipped the prompt — without affecting whether the update prompt appears.

```swift
// checker is @Observable, so this view re-renders automatically.
if checker.availableUpdate != nil {
    UpdateAvailableView()
}
```

`availableUpdate` is set when a check finds a newer, compatible, and sufficiently recent store version — including versions the policy classifies as silent and versions the user has snoozed or skipped. Only a check that confirms the installed version is current clears it. Throttled and failed checks leave it unchanged, so a transient network failure never clears it.

Because `checker` is `@Observable`, SwiftUI views that read `checker.availableUpdate` update automatically whenever it changes.

## Next Steps

For guidance on previewing the update prompt during development and diagnosing suppressed checks, see <doc:Testing>.
