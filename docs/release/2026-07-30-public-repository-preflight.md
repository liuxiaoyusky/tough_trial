# 2026-07-30 Public Repository Preflight

- Branch: `codex/public-release-cleanup`
- Base: `origin/main` at `0fb66d0`
- Candidate version: `1.0 (1)`
- Toolchain: Xcode 26.6 / iPhoneOS SDK 26.5
- Result: local public-source gate passed

This result verifies a source and unsigned build candidate. It is not a signed
Archive, TestFlight upload, or App Store submission.

## Repository Boundary

- Removed tracked local prototype workspaces and unrelated talk material.
- Ignored generated outputs, internal task boards, private handoff notes,
  machine-specific configuration, signing artifacts, and credentials.
- Excluded the personal task-migration CLI and organization-specific
  classification rules from the public Swift package.
- Added a public README with reproducible build, privacy, and licensing
  boundaries.
- Scanned tracked and unignored files for private home paths, concrete Feishu
  resources, assigned credentials, common API tokens, Bearer credentials, and
  private key material.

## Automated Gate

`Tools/release-preflight.sh` passed:

- sensitive information scan
- App Store metadata validation
- privacy manifest validation
- `ToughTrialV2Checks`
- `FocusTimelineCoreChecks`
- `swift build`
- XcodeGen project regeneration
- unsigned generic iPhoneOS Release build
- release product checks for PrivacyInfo and the Live Activity extension
- release product scan for private source markers

## UI Gate

Device: iPhone 17 Pro simulator, iOS 26.5

- Passed: 6
- Failed: 0
- Skipped: 0

Covered:

1. empty first launch
2. primary navigation and plan presentation
3. quick-add submission
4. task map collapse and zoom
5. in-place text/handwriting switching
6. handwriting-only reflection completion

Result bundle:

`/tmp/tough-trial-public-cleanup-tests/Logs/Test/Test-ToughTrial-2026.07.30_17-54-39-+0900.xcresult`

The result-bundle path is local evidence and is not part of the repository.

## Remaining Owner Gates

- Choose an open-source license, or intentionally keep the visible source
  unlicensed.
- Confirm public support identity, email, Privacy Policy URL, and Support URL.
- Confirm iPhone-only versus iPhone and iPad release scope.
- Confirm local-only planning versus a production remote AI service.
- Complete App Privacy, export compliance, age rating, signing, Archive,
  validation, TestFlight, and final App Store submission.
- Approve any remote history rewrite or force-push needed to remove old local
  prototype paths from existing public Git history.
