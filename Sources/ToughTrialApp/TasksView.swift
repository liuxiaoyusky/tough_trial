import FocusTimelineCore
import SwiftUI

struct TasksView: View {
    @ObservedObject var store: DemoAppStore
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        Text("任务")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Spacer()
                        Text("\(store.state.tasks.count) 项")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.72), in: Capsule())
                    }

                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("搜索任务、记录、计划...", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .padding()
                    .background(.white.opacity(0.74), in: Capsule())

                    VStack(spacing: 10) {
                        ForEach(store.state.filteredTasks(matching: searchText)) { task in
                            taskCard(task, isSelected: store.state.selectedFocusTaskID == task.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                                        store.state.selectFocus(taskID: task.id)
                                    }
                                }
                        }
                    }

                    focusCandidate
                }
                .padding(20)
            }
            .dailyScreen()
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder
    private var focusCandidate: some View {
        let candidate = store.state.focusCandidate

        VStack(alignment: .leading, spacing: 12) {
            Text("专注候选")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.ink.opacity(0.62))
            Text(candidate?.title ?? "选择一个任务")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            HStack {
                Button("\(store.state.selectedDurationMinutes) 分钟") {}
                    .buttonStyle(CapsuleButtonStyle())
                Button("完成") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        store.state.completeFocusCandidate(atLabel: "刚刚")
                    }
                }
                .buttonStyle(CapsuleButtonStyle())
                .disabled(candidate == nil)
                Spacer()
                Button("开始") {
                    store.startZen()
                }
                .buttonStyle(CapsuleButtonStyle(filled: true))
                .disabled(candidate == nil)
            }
        }
        .padding(16)
        .background(AppTheme.focusGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func taskCard(_ task: DemoTask, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(task.title)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(task.progressLabel)
                    .font(.caption.weight(.semibold))
            }

            Text(task.detail)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.66) : AppTheme.muted)

            ProgressView(value: task.progressRatio)
                .tint(isSelected ? AppTheme.copper : AppTheme.blue)
        }
        .padding(14)
        .foregroundStyle(isSelected ? Color.white : AppTheme.ink)
        .background(isSelected ? AppTheme.night : Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    TasksView(store: DemoAppStore())
}
