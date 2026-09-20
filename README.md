# Tough Trial

Tough Trial is a native SwiftUI iOS prototype for a lightweight personal task
assistant. It separates four intentions instead of turning every activity into
project management:

- `今天`: focus on today's execution and record real time spent.
- `任务`: understand goals, task structure, history, and possible next work.
- `计划`: turn a low-friction conversation into a reviewable planning draft.
- `回想`: reflect from actual execution evidence with text or handwriting.

The product direction is documented in
[`docs/spec.md`](docs/spec.md). The active implementation lives in
`Sources/ToughTrialV2App/` and `Sources/ToughTrialV2Core/`.

## Requirements

- macOS with Xcode 26 or newer
- iOS 17 deployment target
- Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```bash
swift run ToughTrialV2Checks
swift run FocusTimelineCoreChecks
swift build
xcodegen generate
xcodebuild \
  -project ToughTrial.xcodeproj \
  -scheme ToughTrial \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For the full local release gate:

```bash
Tools/release-preflight.sh
```

## Privacy And AI

- App state, execution records, reflections, and PencilKit drawings are stored
  in the app's local Application Support directory.
- The default planning experience is deterministic and local.
- Remote planning is a development-only adapter and requires an explicitly
  supplied API key. No credential is included in the repository or app bundle.
- Speech recognition requests on-device processing when the device supports it;
  otherwise Apple's speech service may process audio.
- The public repository does not include personal task snapshots, external
  workspace exports, account tokens, or machine-specific paths.

Draft release and privacy materials live in [`docs/release/`](docs/release/).

## Repository Boundaries

Generated screenshots, local prototypes, internal task boards, private handoff
notes, and signing artifacts are intentionally ignored. Run the sensitive
information check before staging public changes:

```bash
node Tools/check-sensitive-info.mjs
```

This repository currently has no open-source license. Source code is visible for
evaluation, but no reuse rights are granted until the owner chooses and adds a
license.
