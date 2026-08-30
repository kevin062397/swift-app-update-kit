# ``SwiftAppUpdateKit``

Detect when a newer version of the host app is available on the App Store and prompt the user to update.

## Overview

SwiftAppUpdateKit runs a check at launch, evaluates the result through an eleven-gate decision pipeline, and presents an update prompt when an update passes every gate. The library never surfaces a network failure or an uninstallable update to the user.

All external inputs — the update policy, the presentation permission, the snooze and throttle intervals — are under the adopting app's control.

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:Testing>

### Checker and Configuration

- ``UpdateChecker``
- ``UpdateCheckConfiguration``
- ``UpdatePolicy``
- ``UpdateRequirement``

### Check Outcomes

- ``UpdateCheckOutcome``
- ``UpdateCheckFailure``
- ``SuppressionReason``
- ``UpdateDescription``

### Version Comparison

- ``AppVersion``
- ``VersionClassification``

### App Store Metadata

- ``AppStoreMetadata``

### Presentation State

- ``PresentationState``
