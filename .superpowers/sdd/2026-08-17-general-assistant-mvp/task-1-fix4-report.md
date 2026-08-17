# Task 1 Fix 4 Report

## Status

Completed. The remaining Trace-subject security finding is addressed.

## Files

- `Sources/ToughTrialV2Core/V2AgentModels.swift`
  - Rebuilds Trace web URLs from scheme, host, optional port, and encoded path only.
  - Stores Trace source and artifact IDs as UUID values and decodes only UUID strings.
- `Checks/ToughTrialV2Checks/AgentWorkspaceChecks.swift`
  - Covers URL userinfo, token/signed query values, and fragments at construction, persistence, and decode boundaries.
  - Covers UUID construction/round trips and rejection of arbitrary, credential-shaped source/artifact IDs.

## Commit Hash

This report is included in the final commit, so its own final commit SHA is recorded in the final task handoff after Git creates that commit.

## Tests

- `swift run ToughTrialV2Checks` - passed
- `swift run FocusTimelineCoreChecks` - passed
- `swift build` - passed
- `git diff --check` - passed

## Deviations

None. The change is limited to the requested Trace models, focused checks, and this required report. Chinese search-query behavior remains covered by the existing readable-query round trip.

## Risks

- Existing persisted Trace subjects with non-UUID source/artifact IDs will now fail decoding. This is intentional under the new strict boundary; no migration was requested.
- URL query and fragment values are intentionally discarded, including legitimate signed URLs, so Trace records retain only a non-secret navigational identity.
