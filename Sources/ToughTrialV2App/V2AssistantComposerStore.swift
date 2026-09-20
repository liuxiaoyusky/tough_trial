import Foundation
import ToughTrialV2Core

extension V2AssistantStore {
    func modelSnapshot(for sessionID: String) throws -> V2AssistantModelSnapshot {
        if let selection = workspace.session(id: sessionID)?.modelSelection {
            guard let factory = dependencies.selectedModelSnapshot else { throw V2AssistantTurnError.providerIdentityChanged }
            return try factory(selection)
        }
        return try dependencies.modelSnapshot()
    }

    @discardableResult
    func selectModel(_ selection: V2AIProviderSelection?, in sessionID: String) -> Bool {
        guard let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else { return false }
        return commitWorkspace { $0.sessions[index].modelSelection = selection }
    }

    func saveDraft(_ draft: V2AssistantDraft, in sessionID: String) {
        guard mayMutate, let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }),
              workspace.sessions[index].composerDraft != draft else { return }
        _ = commitWorkspace(syncArchive: false) { $0.sessions[index].composerDraft = draft }
    }

    @discardableResult
    func submitDraft(_ draft: V2AssistantDraft, source: V2UsageEvent.Source = .keyboard) -> Bool {
        guard mayMutate, V2PluginStore.shared.enabled("assistant"),
              let sessionID = workspace.selectedSessionID,
              let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }),
              !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if currentTurn != nil {
            return commitWorkspace {
                $0.sessions[index].queuedDrafts = ($0.sessions[index].queuedDrafts ?? []) + [draft]
                $0.sessions[index].composerDraft = nil
            }
        }
        let accepted = send(draft.text, inputSource: source, references: draft.references, attachments: draft.attachments ?? [])
        if accepted { _ = commitWorkspace { $0.sessions[index].composerDraft = nil } }
        return accepted
    }

    func removeQueuedDraft(_ id: String, in sessionID: String) {
        guard let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        _ = commitWorkspace { $0.sessions[index].queuedDrafts?.removeAll { $0.id == id } }
    }

    /// Restarted or stopped sessions keep queued messages visible until resumed.
    func sendNextQueuedDraft(in sessionID: String) {
        guard currentTurn == nil, mayMutate, V2PluginStore.shared.enabled("assistant"),
              let draft = workspace.session(id: sessionID)?.queuedDrafts?.first else { return }
        if send(draft.text, references: draft.references, attachments: draft.attachments ?? [], sessionID: sessionID) {
            removeQueuedDraft(draft.id, in: sessionID)
        }
    }
}
