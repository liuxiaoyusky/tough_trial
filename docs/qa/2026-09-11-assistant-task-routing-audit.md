# Latest assistant session: task routing audit

Inspected the physical device workspace and session archive locally on 2026-09-11. No private conversation was replayed to an external provider.

## Observed result

Latest selected session: `D56695F1-49C3-400C-B6A8-91D4DE96E0E1`. Its latest retried response used MiniMax-M2.5-highspeed, completed in 4.880 seconds, and contained only text plus a trace summary. It summarized three activities and asked whether to create tasks or arrange their order. There was no plan, schedule or business tool receipt. “我记下了” therefore did not establish that any tasks were saved.

The request context event includes an available source task reference, compact revision 5, nine conversation messages, and zero native tool exchanges/results at the initial request. The archive does not persist the full request tool catalog, so it cannot prove which descriptors were included in that exact request.

## Code evidence

- `V2AgentClient.systemInstruction` includes a general assistant role, plan/schedule guidance and a dynamic list of tool IDs, purposes and field names.
- API `tools[].function.parameters` carries typed input schemas for enabled registered tools.
- `V2PlanningClient` has a separate structured plan schema, including up to three `suggested_replies`. This schema is sent when the planning client runs, not automatically for every chat response.
- Plugin manifests/packages do not currently supply an assistant skill/workflow instruction registry. Tool descriptions do not fully specify when to route mixed or dictated input into domain artifacts.
- `V2AgentMessagePart` supports text, trace, sources, plan, schedule, tool and error. Ordinary text replies have no independent choices contract. A text bullet list does not become buttons; the separate planning flow already has structured suggested replies.
- `V2AssistantWriteIntent` requires explicit operation markers or a qualifying adjacent clarification for automatic writes. An enumerated “today I need to do these things” statement is not a dedicated intent in that policy. The review-only route exists, but requires the model to request a tool first.

## Design gap

Understanding the activities, routing them to the correct capability, generating typed proposals, and rendering actionable UI are separate steps. The latest response stopped at the first step. A capability workflow layer needs to connect natural input, permitted draft/write behavior, tool schemas and artifact types. Adding more parsing tolerance or keyword triggers alone would not ensure that connection.

The user’s term “three options” is ambiguous between three task cards and three selectable next actions; clarification was requested. No production changes were made during this audit. The expected task-list behavior should be pinned down before changing that UI contract.

The user subsequently confirmed task cards as the primary result with action buttons as auxiliary controls. Implementation and physical-device acceptance are documented in [task-card acceptance](2026-09-11-assistant-task-cards.md).
