import Foundation
import ToughTrialV2Core

extension V2AppStore {
    func assistantModelSnapshot(selection: V2AIProviderSelection) throws -> V2AssistantModelSnapshot {
        guard let provider = V2AIProviderPreset(rawValue: selection.providerID) else { throw V2AssistantTurnError.providerIdentityChanged }
        var settings = aiProviderProfile(for: provider)
        settings.model = selection.model; settings.thinking = selection.thinking; settings.isEnabled = true
        let client = try settings.agentClient()
        let planning = V2ValidatedPlanningClient(client: V2OpenAICompatiblePlanningClient(configuration: try settings.planningConfiguration()))
        let schedule = V2OpenAICompatibleScheduleClient(configuration: try settings.agentConfiguration())
        return V2AssistantModelSnapshot(identity: .init(key: "\(provider.rawValue)|\(settings.baseURL)|\(settings.model)|\(settings.thinking.rawValue)", label: client.providerLabel, model: settings.model),
            respond: { request in try await client.respond(request) },
            generatePlan: { [weak self] session, query, date in
                guard let self else { throw V2AssistantTurnError.planUnavailable }
                return try await self.assistantPlanningOutcome(session: session, query: query, at: date, using: planning)
            }, generateSchedule: { request in try await schedule.generate(request) }, thinking: settings.thinking)
    }
}
