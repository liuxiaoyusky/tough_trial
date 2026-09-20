import Foundation
import SwiftUI

struct V2NavigationPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    var schemaVersion: Int = currentSchemaVersion
    var orderedTabIDs: [String]
}

enum V2NavigationID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case assistant, today, tasks, capture, recall, ownProfile, morePlugins
    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: "助手"
        case .today: "今天"
        case .tasks: "任务"
        case .capture: "随手记"
        case .recall: "回想"
        case .ownProfile: "我的资料"
        case .morePlugins: "更多插件"
        }
    }

    var systemImage: String {
        switch self {
        case .assistant: "sparkles"
        case .today: "calendar"
        case .tasks: "square.stack.3d.up"
        case .capture: "square.and.pencil"
        case .recall: "clock.arrow.circlepath"
        case .ownProfile: "person.crop.circle"
        case .morePlugins: "ellipsis.circle"
        }
    }

    var requiredModuleID: String? {
        switch self {
        case .assistant: "assistant"
        case .today, .tasks: "tasks"
        case .capture: "capture"
        case .recall: "recall"
        case .ownProfile, .morePlugins: nil
        }
    }
}

@MainActor
final class V2NavigationStore: ObservableObject {
    static let shared = V2NavigationStore()
    @Published private(set) var preferences: V2NavigationPreferences

    private let defaults: UserDefaults
    private let storageKey = "navigation.preferences.v1"

    init(defaults: UserDefaults? = nil) {
        let testing = ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.defaults = defaults ?? (testing ? UserDefaults(suiteName: "navigation-ui-\(UUID().uuidString)")! : .standard)
        if let data = self.defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(V2NavigationPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = V2NavigationPreferences(orderedTabIDs: ["assistant", "today", "tasks", "capture", "morePlugins"])
        }
    }

    var orderedTabs: [V2NavigationID] {
        preferences.orderedTabIDs.compactMap(V2NavigationID.init(rawValue:))
    }

    func reconcile(availableIDs: Set<V2NavigationID>) {
        let normalized = Self.normalize(preferences.orderedTabIDs, availableIDs: availableIDs)
        guard normalized != preferences.orderedTabIDs else { return }
        preferences.orderedTabIDs = normalized
        save()
    }

    func add(_ id: V2NavigationID, availableIDs: Set<V2NavigationID>) -> Bool {
        guard id != .morePlugins, availableIDs.contains(id), orderedTabs.count < 5 else { return false }
        guard !preferences.orderedTabIDs.contains(id.rawValue) else { return true }
        let index = preferences.orderedTabIDs.firstIndex(of: V2NavigationID.morePlugins.rawValue) ?? preferences.orderedTabIDs.endIndex
        preferences.orderedTabIDs.insert(id.rawValue, at: index)
        preferences.orderedTabIDs = Self.normalize(preferences.orderedTabIDs, availableIDs: availableIDs)
        save()
        return true
    }

    func remove(_ id: V2NavigationID, availableIDs: Set<V2NavigationID>) -> Bool {
        guard id != .morePlugins, orderedTabs.count > 2 else { return false }
        preferences.orderedTabIDs.removeAll { $0 == id.rawValue }
        preferences.orderedTabIDs = Self.normalize(preferences.orderedTabIDs, availableIDs: availableIDs)
        save()
        return true
    }

    func move(fromOffsets: IndexSet, toOffset: Int, availableIDs: Set<V2NavigationID>) {
        var ids = preferences.orderedTabIDs
        ids.move(fromOffsets: fromOffsets, toOffset: toOffset)
        preferences.orderedTabIDs = Self.normalize(ids, availableIDs: availableIDs)
        save()
    }

    func move(_ dragged: V2NavigationID, before target: V2NavigationID, availableIDs: Set<V2NavigationID>) {
        guard dragged != target else { return }
        var ids = preferences.orderedTabIDs
        guard let source = ids.firstIndex(of: dragged.rawValue), let destination = ids.firstIndex(of: target.rawValue) else { return }
        let value = ids.remove(at: source)
        let adjusted = source < destination ? destination - 1 : destination
        ids.insert(value, at: adjusted)
        preferences.orderedTabIDs = Self.normalize(ids, availableIDs: availableIDs)
        save()
    }

    static func normalize(_ rawIDs: [String], availableIDs: Set<V2NavigationID>) -> [String] {
        let available = availableIDs.union([.morePlugins])
        var result: [V2NavigationID] = []
        for raw in rawIDs {
            guard let id = V2NavigationID(rawValue: raw), available.contains(id), !result.contains(id) else { continue }
            result.append(id)
        }
        if !result.contains(.morePlugins) { result.append(.morePlugins) }
        while result.count > 5 {
            if let index = result.lastIndex(where: { $0 != .morePlugins }) { result.remove(at: index) }
            else { break }
        }
        if result.count < 2, let fallback = V2NavigationID.allCases.first(where: { $0 != .morePlugins && available.contains($0) }) {
            result.insert(fallback, at: 0)
        }
        return result.map(\.rawValue)
    }

    private func save() {
        preferences.schemaVersion = V2NavigationPreferences.currentSchemaVersion
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: storageKey) }
    }
}
