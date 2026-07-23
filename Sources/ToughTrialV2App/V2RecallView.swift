import SwiftUI
import ToughTrialV2Core

struct V2RecallView: View {
    @ObservedObject var store: V2AppStore
    @State private var selectedReferenceKind = V2RecallReferenceCandidate.Kind.event
    @State private var showsReferences: Bool
    @State private var showsHandwriting = false
    @State private var saveStatus = ""
    @FocusState private var isEditorFocused: Bool

    private let calendar = Calendar.current

    init(store: V2AppStore, initiallyShowsReferences: Bool = false) {
        self.store = store
        _showsReferences = State(initialValue: initiallyShowsReferences)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                header

                ZStack(alignment: .topTrailing) {
                    HStack(alignment: .top, spacing: 14) {
                        if !store.state.isRecallFullscreen {
                            dateRail
                                .frame(width: 48)
                        }

                        editor
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if showsReferences && !store.state.isRecallFullscreen {
                        referenceWindow
                            .frame(
                                width: min(292, proxy.size.width - 70),
                                height: min(420, proxy.size.height * 0.58),
                                alignment: .top
                            )
                            .padding(.top, 8)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)

                actionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy(duration: 0.24), value: showsReferences)
            .animation(.snappy(duration: 0.24), value: store.state.isRecallFullscreen)
            .toolbar(store.state.isRecallFullscreen ? .hidden : .visible, for: .tabBar)
            .alert("操作未完成", isPresented: errorBinding) {
                Button("知道了") { store.dismissError() }
            } message: {
                Text(store.errorMessage ?? "请稍后再试。")
            }
            .fullScreenCover(isPresented: $showsHandwriting) {
                V2RecallHandwritingView(date: store.recallDate)
            }
            .v2ScreenBackground()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                store.state.toggleRecallFullscreen()
                if store.state.isRecallFullscreen {
                    showsReferences = false
                }
            } label: {
                Image(
                    systemName: store.state.isRecallFullscreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(V2Theme.ColorRole.textPrimary)
                .frame(width: 38, height: 38)
                .background(V2Theme.ColorRole.surfaceRaised)
                .clipShape(Circle())
                .overlay(Circle().stroke(V2Theme.ColorRole.outline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.state.isRecallFullscreen ? "退出全屏" : "全屏回想")

            VStack(alignment: .leading, spacing: 2) {
                Text("回想")
                    .font(V2Theme.TypeRole.headlineSmall)
                    .foregroundStyle(V2Theme.ColorRole.textPrimary)

                Text(Self.headerDateFormatter.string(from: store.recallDate))
                    .font(V2Theme.TypeRole.labelSmall)
                    .foregroundStyle(V2Theme.ColorRole.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var dateRail: some View {
        VStack(spacing: 8) {
            ForEach(recallDates, id: \.timeIntervalSinceReferenceDate) { date in
                let selected = calendar.isDate(date, inSameDayAs: store.recallDate)

                Button {
                    store.selectRecallDate(date)
                    saveStatus = ""
                    showsReferences = false
                } label: {
                    VStack(spacing: 2) {
                        Text(Self.weekdayFormatter.string(from: date))
                            .font(.system(size: 9, weight: .semibold))
                        Text(Self.dayFormatter.string(from: date))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selected ? V2Theme.ColorRole.textInverse : V2Theme.ColorRole.textSecondary)
                    .frame(width: 42, height: selected ? 58 : 46)
                    .background(selected ? V2Theme.ColorRole.textPrimary : Color.clear)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.accessibleDateFormatter.string(from: date))
            }

            Spacer(minLength: 0)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: recallTextBinding)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(V2Theme.ColorRole.textPrimary)
                    .lineSpacing(7)
                    .scrollContentBackground(.hidden)
                    .focused($isEditorFocused)
                    .padding(.horizontal, -5)
                    .padding(.vertical, -7)
                    .background(.clear)

                if store.recallText.isEmpty {
                    Text(recallPlaceholder)
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .foregroundStyle(V2Theme.ColorRole.textTertiary)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                if !store.selectedRecallCandidateIDs.isEmpty {
                    Button {
                        showsReferences = true
                    } label: {
                        Label(
                            "已引用 \(store.selectedRecallCandidateIDs.count) 条",
                            systemImage: "quote.opening"
                        )
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.ColorRole.onPrimaryContainer)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                if !saveStatus.isEmpty {
                    Text(saveStatus)
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.ColorRole.taskComplete)
                }
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(V2Theme.ColorRole.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.ColorRole.outline.opacity(0.72), lineWidth: 1)
        }
    }

    private var referenceWindow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("引用证据")
                    .font(V2Theme.TypeRole.titleMedium)
                    .foregroundStyle(V2Theme.ColorRole.textPrimary)

                Spacer()

                Button {
                    showsReferences = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V2Theme.ColorRole.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭证据")
            }

            referenceKindPicker

            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredCandidates.isEmpty {
                        Text(emptyReferenceText)
                            .font(V2Theme.TypeRole.bodySmall)
                            .foregroundStyle(V2Theme.ColorRole.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(Array(filteredCandidates.enumerated()), id: \.element.id) { index, candidate in
                            referenceRow(candidate)

                            if index < filteredCandidates.count - 1 {
                                Divider()
                                    .overlay(V2Theme.ColorRole.outline.opacity(0.7))
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(V2Theme.ColorRole.surfaceRaised.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.ColorRole.outline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.11), radius: 24, y: 10)
    }

    private var referenceKindPicker: some View {
        HStack(spacing: 4) {
            ForEach(V2RecallReferenceCandidate.Kind.allCasesForView, id: \.self) { kind in
                Button {
                    selectedReferenceKind = kind
                } label: {
                    Text(kind.displayName)
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(
                            selectedReferenceKind == kind
                                ? V2Theme.ColorRole.textInverse
                                : V2Theme.ColorRole.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            selectedReferenceKind == kind
                                ? V2Theme.ColorRole.textPrimary
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(V2Theme.ColorRole.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func referenceRow(_ candidate: V2RecallReferenceCandidate) -> some View {
        Button {
            store.toggleRecallReference(candidate)
            saveStatus = ""
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.title)
                        .font(V2Theme.TypeRole.labelMedium)
                        .foregroundStyle(V2Theme.ColorRole.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(candidate.detail)
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.ColorRole.textTertiary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                Image(
                    systemName: store.isRecallReferenceSelected(candidate)
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    store.isRecallReferenceSelected(candidate)
                        ? V2Theme.ColorRole.primary
                        : V2Theme.ColorRole.outline
                )
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                showsHandwriting = true
            } label: {
                Label("手写", systemImage: "pencil.tip")
            }
            .buttonStyle(RecallToolbarButtonStyle(isPrimary: false))

            if !store.state.isRecallFullscreen {
                Button {
                    showsReferences.toggle()
                } label: {
                    Label("引用", systemImage: "quote.opening")
                }
                .buttonStyle(RecallToolbarButtonStyle(isPrimary: false))
            }

            Spacer(minLength: 0)

            Button {
                if store.saveRecall() {
                    saveStatus = "已保存"
                    isEditorFocused = false
                }
            } label: {
                Label("保存", systemImage: "checkmark")
            }
            .buttonStyle(RecallToolbarButtonStyle(isPrimary: true))
            .disabled(store.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(V2Theme.ColorRole.canvas)
    }

    private var recallDates: [Date] {
        (0..<4).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: Date()))
        }
    }

    private var filteredCandidates: [V2RecallReferenceCandidate] {
        store.recallCandidates.filter { $0.kind == selectedReferenceKind }
    }

    private var emptyReferenceText: String {
        switch selectedReferenceKind {
        case .event:
            "这一天还没有执行记录。"
        case .deviation:
            "暂时没有可以判断的计划偏差。"
        case .past:
            "最近还没有可以引用的事件。"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: {
                if !$0 { store.dismissError() }
            }
        )
    }

    private var recallTextBinding: Binding<String> {
        Binding(
            get: { store.recallText },
            set: {
                store.updateRecallText($0)
                saveStatus = ""
            }
        )
    }

    private var recallPlaceholder: String {
        calendar.isDateInToday(store.recallDate)
            ? "写下今天真正发生了什么..."
            : "写下这一天真正发生了什么..."
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let accessibleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
}

private struct RecallToolbarButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(V2Theme.TypeRole.labelMedium)
            .foregroundStyle(
                isPrimary
                    ? V2Theme.ColorRole.onPrimary
                    : V2Theme.ColorRole.textPrimary
            )
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                isPrimary
                    ? V2Theme.ColorRole.primary
                    : V2Theme.ColorRole.surfaceRaised
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isPrimary ? Color.clear : V2Theme.ColorRole.outline,
                        lineWidth: 1
                    )
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private extension V2RecallReferenceCandidate.Kind {
    static let allCasesForView: [Self] = [.event, .deviation, .past]

    var displayName: String {
        switch self {
        case .event:
            "事件"
        case .deviation:
            "偏差"
        case .past:
            "过去"
        }
    }
}
