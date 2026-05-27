import SwiftUI

struct TasksView: View {
    @State private var selectedTask = "写作提纲"
    @State private var showZenMode = false

    private let tasks = [
        TaskRow(title: "本周跑 5 次 3 公里", detail: "系列任务 · 本周目标", progress: "2/5", ratio: 0.4),
        TaskRow(title: "写作提纲", detail: "点击后进入专注候选，而不是立即开始", progress: "今天", ratio: 0.62),
        TaskRow(title: "读完这本书", detail: "累计任务 · 按页数记录", progress: "50/1000", ratio: 0.05)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        Text("任务")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Spacer()
                        Text("12 项")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.72), in: Capsule())
                    }

                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("搜索任务、记录、计划...")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .padding()
                    .background(.white.opacity(0.74), in: Capsule())

                    VStack(spacing: 10) {
                        ForEach(tasks) { task in
                            taskCard(task, isSelected: selectedTask == task.title)
                                .onTapGesture {
                                    selectedTask = task.title
                                }
                        }
                    }

                    focusCandidate
                }
                .padding(20)
            }
            .dailyScreen()
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showZenMode) {
                ZenModeView(taskTitle: selectedTask)
            }
        }
    }

    private var focusCandidate: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("专注候选")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.ink.opacity(0.62))
            Text(selectedTask)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            HStack {
                Button("25 分钟") {}
                    .buttonStyle(CapsuleButtonStyle())
                Spacer()
                Button("开始") {
                    showZenMode = true
                }
                .buttonStyle(CapsuleButtonStyle(filled: true))
            }
        }
        .padding(16)
        .background(AppTheme.focusGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func taskCard(_ task: TaskRow, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(task.title)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(task.progress)
                    .font(.caption.weight(.semibold))
            }

            Text(task.detail)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.66) : AppTheme.muted)

            ProgressView(value: task.ratio)
                .tint(isSelected ? AppTheme.copper : AppTheme.blue)
        }
        .padding(14)
        .foregroundStyle(isSelected ? Color.white : AppTheme.ink)
        .background(isSelected ? AppTheme.night : Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TaskRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let progress: String
    let ratio: Double
}

#Preview {
    TasksView()
}
