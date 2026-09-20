import SwiftUI

struct V2MorePluginsView: View {
    @ObservedObject var appStore: V2AppStore
    @ObservedObject var navigation: V2NavigationStore
    let availableIDs: Set<V2NavigationID>
    let openModule: (V2NavigationID) -> Void

    private var hiddenModules: [V2NavigationID] {
        V2NavigationID.allCases.filter {
            $0 != .morePlugins && availableIDs.contains($0) && !navigation.orderedTabs.contains($0)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        V2EditBottomNavigationView(navigation: navigation, availableIDs: availableIDs)
                    } label: {
                        Label("编辑底部导航", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("morePlugins.editNavigation")
                }

                Section("已启用") {
                    if hiddenModules.isEmpty {
                        Text("所有可用模块都已经放到底栏。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(hiddenModules) { item in
                            Button {
                                openModule(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.systemImage)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).foregroundStyle(.primary)
                                        Text("点按打开，不会自动加入底栏")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("morePlugins.open.\(item.rawValue)")
                        }
                    }
                }

                Section("已放到底栏") {
                    ForEach(navigation.orderedTabs.filter { $0 != .morePlugins }) { item in
                        Label(item.title, systemImage: item.systemImage)
                    }
                }

                Section {
                    NavigationLink {
                        V2PluginsView(appStore: appStore)
                    } label: {
                        Label("功能与插件设置", systemImage: "puzzlepiece.extension")
                    }
                    .accessibilityIdentifier("morePlugins.settings")
                } footer: {
                    Text("这里负责启用、停用、安装与权限；底栏只决定常用入口。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(V2Theme.page)
            .navigationTitle("更多插件")
        }
    }
}

private struct V2EditBottomNavigationView: View {
    @ObservedObject var navigation: V2NavigationStore
    let availableIDs: Set<V2NavigationID>

    private var addable: [V2NavigationID] {
        V2NavigationID.allCases.filter {
            $0 != .morePlugins && availableIDs.contains($0) && !navigation.orderedTabs.contains($0)
        }
    }

    var body: some View {
        List {
            Section("底栏中的项目") {
                ForEach(navigation.orderedTabs) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.systemImage).frame(width: 28)
                        Text(item.title)
                        Spacer()
                        if item == .morePlugins {
                            Text("必选").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("移除", role: .destructive) {
                                _ = navigation.remove(item, availableIDs: availableIDs)
                            }
                            .disabled(navigation.orderedTabs.count <= 2)
                            .accessibilityIdentifier("navigation.remove.\(item.rawValue)")
                        }
                    }
                }
                .onMove { offsets, destination in
                    navigation.move(fromOffsets: offsets, toOffset: destination, availableIDs: availableIDs)
                }
            }

            Section("可添加") {
                if addable.isEmpty {
                    Text(navigation.orderedTabs.count >= 5 ? "底栏最多显示 5 个入口。" : "没有其他可添加模块。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(addable) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.systemImage).frame(width: 28)
                            Text(item.title)
                            Spacer()
                            Button {
                                _ = navigation.add(item, availableIDs: availableIDs)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .disabled(navigation.orderedTabs.count >= 5)
                            .accessibilityLabel("添加\(item.title)到底栏")
                            .accessibilityIdentifier("navigation.add.\(item.rawValue)")
                        }
                    }
                }
            }
        }
#if os(iOS)
        .environment(\.editMode, .constant(.active))
#endif
        .navigationTitle("编辑底部导航")
        .v2InlineNavigationTitle()
    }
}
