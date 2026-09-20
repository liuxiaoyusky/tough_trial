# Public Release File Boundary

## Included

The public release branch contains only files needed to understand, build, or
verify the product:

- `Package.swift`, `project.yml`, and the generated shared Xcode project
- `Sources/ToughTrialV2App/` and `Sources/ToughTrialV2Core/`
- `Sources/ToughTrialActivityShared/` and `Sources/ToughTrialLiveActivity/`
- the compatibility core already present under `Sources/FocusTimelineCore/`
- checks and UI tests under `Checks/` and `Tests/`
- public product specs, selected QA evidence, and release/privacy drafts
- reproducible release tools under `Tools/`

The superseded SwiftUI app under `Sources/ToughTrialApp/` is intentionally not
included. Its history remains on local backup branches, not in the public
release candidate.

## Excluded

The following are local-only and covered by `.gitignore`:

- personal task snapshots and external workspace exports
- account tokens, API keys, signing identities, provisioning profiles, and
  machine-specific configuration
- local prototype workspaces, generated outputs, and browser automation traces
- internal task boards, handoff notes, collaboration logs, and unrelated talks
- private data migration scripts containing organization- or user-specific
  classification rules

The app does not require any excluded file to build or launch from an empty
installation.

## Public Release Gate

Before publishing a commit:

1. Run `node Tools/check-sensitive-info.mjs`.
2. Run `Tools/release-preflight.sh`.
3. Review `git status --short` and stage an explicit file set.
4. Verify the commit from a clean checkout or detached worktree.
5. Configure signing, Archive, validation, and App Store Connect only after the
   repository gate passes.

License selection, public support identity, App Privacy answers, export
compliance, and final App Store submission remain owner decisions.
