# Assistant tool continuation — 2026-09-11

## Incident and limits of the earlier acceptance

The latest device session contained two failed turns: invalid operation JSON, then rejection of multiple native tool calls. Its final turn succeeded. Authentication was working; the second failed turn read the same session twice before receiving the rejected batch. Private response bodies were not recorded, so the exact malformed response cannot be reconstructed.

Earlier connection verification proved credentials, endpoint access and one short answer. It did not prove multi-round tool conversation correctness. This was an implementation and acceptance gap.

## Protocol contract

- Registered commands use native API functions. Legacy JSON actions remain decodable for existing providers, but the prompt no longer tells models to use two competing command formats.
- Ordinary text is display-only. A fully fenced JSON response is unwrapped. Malformed JSON-looking operations still fail closed; narration never becomes a write.
- Preserve the native assistant tool-call message and pair each actual result with its call ID as a `role: tool` message on the next model request. MiniMax's `reasoning_details` / `reasoning_content` are opaque, ephemeral continuation data; do not persist them to workspace or trace.
- Validate all calls against the current catalog before starting a batch. Execute sequentially, within the existing six-call turn budget. Unknown tools, duplicate call IDs and invalid arguments are rejected.
- Stop at pending confirmation, missing information, blocked, conflict, failure or cancellation. Do not execute later calls in that batch. Existing host authorization, receipt recovery and undo rules remain in force.
- Trace context manifests add native exchange and result counts, without tool payloads or provider reasoning.

MiniMax's [official OpenAI compatibility documentation](https://platform.minimax.io/docs/api-reference/text-openai-api) requires complete tool-call continuation and retention of separated reasoning metadata during the conversation.

## Acceptance evidence

| Scenario | Evidence |
| --- | --- |
| Ordinary answer / fenced answer / malformed operation | Core `V2ToolWireTests` |
| Portable native names, multiple calls, paired results and preserved continuation | Core `V2ToolWireTests` |
| Unknown later call / duplicate IDs | Entire batch rejected before execution |
| Two real host context tools in order | App context integration test checks memory and session text in the next request |
| Confirmation boundary | App test verifies one pending receipt, zero created tasks, no second operation |
| Invalid later call | App test verifies zero operations |
| Reasoning not persisted | App test encodes final workspace and verifies opaque provider fixture is absent |
| Existing cancellation, provider identity and receipt recovery | Assistant store and dynamic recovery regression suites |
| Live MiniMax dependent tools | Passed on iPhone 13 Pro: MiniMax-M2.7-highspeed, two dependent native calls, actual final result verified, 5.504 seconds |

Core: final run passed 212 tests, five opt-in tests skipped, zero failures (`/private/tmp/tough-session-core-all.log`). App: final 36 selected tests passed (context integration, assistant store, dynamic recovery; `/private/tmp/tough-session-app-final.log`). `ToughTrialV2Checks` passed after updating the obsolete single-tool-only prompt assertion.

First live attempt failed its native-continuation assertion: the conflicting prompt caused MiniMax to choose legacy JSON commands. This was not accepted as a successful multi-round test. The conflicting instruction and example were removed before retrying.

Live tests use only two synthetic read-only functions. The second requires a random token returned by the first; the final answer must contain a different random result. The test does not replay private phone conversations or read personal business data. It verifies provider protocol continuity; local App integration tests separately verify actual host operations.

A subsequent live attempt resumed after unlock and reached the second native call, but the synthetic fixture used the reserved credential field name `token`. The fixture was corrected to `lookupCode`; production validation was preserved. The final run passed (`/private/tmp/tough-session-minimax-live.log`, `MINIMAX_NATIVE_TOOLS_OK`, 5.504 seconds).

Installation: version 1.0 (8) signed build installed by Xcode on iPhone 13 Pro. Final live test passed; `devicectl` normal launch succeeded at 17:18:02. No personal business records were created by the synthetic test.

Remaining coverage: no claim of exhaustive scenarios or all-provider live compatibility. Long-session exhaustion, provider timeouts during multi-step work and broader provider-specific live matrices remain follow-up acceptance work.
