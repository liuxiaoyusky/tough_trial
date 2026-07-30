import PencilKit
import SwiftUI
import ToughTrialV2Core
import UIKit

enum V2RecallInputMode: String {
    case text
    case handwriting
}

struct V2RecallView: View {
    @ObservedObject var store: V2AppStore
    @State private var selectedReferenceKind = V2RecallReferenceCandidate.Kind.event
    @State private var showsReferences: Bool
    @State private var inputMode: V2RecallInputMode
    @State private var drawing: PKDrawing
    @State private var drawingDrafts: [Date: V2RecallDrawingDraft] = [:]
    @State private var isDrawingDirty = false
    @State private var selectedCanvasTool = V2RecallCanvasTool.pen
    @State private var inkColor = V2Theme.ColorRole.primary
    @State private var isEditorFocused = false
    @State private var drawingErrorMessage: String?

    private let calendar = Calendar.current
    private let drawingStore: V2RecallDrawingStore

    init(
        store: V2AppStore,
        initiallyShowsReferences: Bool = false,
        initialInputMode: V2RecallInputMode = .text,
        drawingStore: V2RecallDrawingStore = V2RecallDrawingStore()
    ) {
        self.store = store
        self.drawingStore = drawingStore
        _showsReferences = State(initialValue: initiallyShowsReferences)
        _inputMode = State(initialValue: initialInputMode)
        _drawing = State(initialValue: drawingStore.load(for: store.recallDate))
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
                Button("知道了") {
                    drawingErrorMessage = nil
                    store.dismissError()
                }
            } message: {
                Text(drawingErrorMessage ?? store.errorMessage ?? "请稍后再试。")
            }
            .onDisappear(perform: cacheDrawingDraft)
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

            if !store.state.isRecallFullscreen {
                VStack(alignment: .leading, spacing: 2) {
                    Text("回想")
                        .font(V2Theme.TypeRole.headlineSmall)
                        .foregroundStyle(V2Theme.ColorRole.textPrimary)

                    Text(Self.headerDateFormatter.string(from: store.recallDate))
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(V2Theme.ColorRole.textTertiary)
                }
            }

            Spacer(minLength: 0)

            modeSwitch
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var modeSwitch: some View {
        HStack(spacing: 3) {
            modeButton(
                mode: .text,
                title: "文字",
                systemImage: "textformat"
            )
            modeButton(
                mode: .handwriting,
                title: "手写",
                systemImage: "pencil.tip"
            )
        }
        .padding(3)
        .background(V2Theme.ColorRole.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("回想输入方式")
    }

    private func modeButton(
        mode: V2RecallInputMode,
        title: String,
        systemImage: String
    ) -> some View {
        Button {
            selectInputMode(mode)
        } label: {
            Label(title, systemImage: systemImage)
                .font(V2Theme.TypeRole.labelMedium)
                .foregroundStyle(
                    inputMode == mode
                        ? V2Theme.ColorRole.textPrimary
                        : V2Theme.ColorRole.textSecondary
                )
                .frame(width: 72, height: 34)
                .background(
                    inputMode == mode
                        ? V2Theme.ColorRole.surfaceRaised
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(
                    color: inputMode == mode ? .black.opacity(0.07) : .clear,
                    radius: 6,
                    y: 2
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            mode == .text ? "recall.mode.text" : "recall.mode.handwriting"
        )
        .accessibilityValue(inputMode == mode ? "已选择" : "未选择")
    }

    private var dateRail: some View {
        VStack(spacing: 8) {
            ForEach(recallDates, id: \.timeIntervalSinceReferenceDate) { date in
                let selected = calendar.isDate(date, inSameDayAs: store.recallDate)

                Button {
                    selectRecallDate(date)
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
            HStack(spacing: 8) {
                Text(paperTitle)
                    .font(V2Theme.TypeRole.labelLarge)
                    .foregroundStyle(V2Theme.ColorRole.textTertiary)

                Spacer(minLength: 0)

                if showsSaveState {
                    Circle()
                        .fill(isRecallDirty ? V2Theme.ColorRole.textTertiary : V2Theme.ColorRole.taskComplete)
                        .frame(width: 7, height: 7)

                    Text(isRecallDirty ? "未保存" : "已保存")
                        .font(V2Theme.TypeRole.labelSmall)
                        .foregroundStyle(
                            isRecallDirty
                                ? V2Theme.ColorRole.textTertiary
                                : V2Theme.ColorRole.taskComplete
                        )
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Divider()
                .overlay(V2Theme.ColorRole.outline.opacity(0.72))

            Group {
                switch inputMode {
                case .text:
                    textEditor
                case .handwriting:
                    V2RecallHandwritingCanvas(
                        drawing: $drawing,
                        selectedTool: $selectedCanvasTool,
                        inkColor: $inkColor,
                        onDrawingChanged: {
                            isDrawingDirty = true
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(V2Theme.ColorRole.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.ColorRole.outline.opacity(0.72), lineWidth: 1)
        }
    }

    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            V2RecallTextEditor(
                text: recallTextBinding,
                isFocused: $isEditorFocused,
                onPencilInput: {
                    selectInputMode(.handwriting)
                }
            )

            if store.recallText.isEmpty {
                Text(recallPlaceholder)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(V2Theme.ColorRole.textTertiary)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            isEditorFocused = true
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
            if !store.state.isRecallFullscreen {
                Button {
                    showsReferences.toggle()
                } label: {
                    Label(referenceButtonTitle, systemImage: "quote.opening")
                }
                .buttonStyle(RecallToolbarButtonStyle(isPrimary: false))
            }

            Spacer(minLength: 0)

            Button {
                completeRecall()
            } label: {
                Label("完成", systemImage: "checkmark")
            }
            .buttonStyle(RecallToolbarButtonStyle(isPrimary: true))
            .disabled(!canCompleteRecall)
            .accessibilityIdentifier("recall.complete")
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
            get: { drawingErrorMessage != nil || store.errorMessage != nil },
            set: {
                if !$0 {
                    drawingErrorMessage = nil
                    store.dismissError()
                }
            }
        )
    }

    private var recallTextBinding: Binding<String> {
        Binding(
            get: { store.recallText },
            set: {
                store.updateRecallText($0)
            }
        )
    }

    private var recallPlaceholder: String {
        calendar.isDateInToday(store.recallDate)
            ? "今天最值得记录的是……"
            : "这一天最值得记录的是……"
    }

    private var paperTitle: String {
        calendar.isDateInToday(store.recallDate)
            ? "今天的回想"
            : Self.paperDateFormatter.string(from: store.recallDate)
    }

    private var isRecallDirty: Bool {
        store.isRecallDirty || isDrawingDirty
    }

    private var showsSaveState: Bool {
        isRecallDirty
            || store.savedRecallEntry != nil
            || !drawing.strokes.isEmpty
    }

    private var canCompleteRecall: Bool {
        !store.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !drawing.strokes.isEmpty
    }

    private var referenceButtonTitle: String {
        let count = store.selectedRecallCandidateIDs.count
        return count == 0 ? "引用" : "引用 \(count)"
    }

    private func selectInputMode(_ mode: V2RecallInputMode) {
        inputMode = mode
        showsReferences = false

        switch mode {
        case .text:
            DispatchQueue.main.async {
                isEditorFocused = true
            }
        case .handwriting:
            isEditorFocused = false
        }
    }

    private func selectRecallDate(_ date: Date) {
        cacheDrawingDraft()
        isEditorFocused = false
        showsReferences = false
        store.selectRecallDate(date)

        let day = calendar.startOfDay(for: store.recallDate)
        if let draft = drawingDrafts[day] {
            drawing = draft.drawing
            isDrawingDirty = draft.isDirty
        } else {
            drawing = drawingStore.load(for: day)
            isDrawingDirty = false
        }
    }

    private func cacheDrawingDraft() {
        let day = calendar.startOfDay(for: store.recallDate)
        drawingDrafts[day] = V2RecallDrawingDraft(
            drawing: drawing,
            isDirty: isDrawingDirty
        )
    }

    private func completeRecall() {
        let hasHandwriting = !drawing.strokes.isEmpty

        do {
            try drawingStore.save(drawing, for: store.recallDate)
        } catch {
            drawingErrorMessage = "手写内容没有保存，请稍后再试。"
            return
        }

        guard store.saveRecall(hasHandwriting: hasHandwriting) else {
            return
        }

        isDrawingDirty = false
        cacheDrawingDraft()
        isEditorFocused = false
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

    private static let paperDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日的回想"
        return formatter
    }()

    private static let accessibleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
}

private struct V2RecallDrawingDraft {
    var drawing: PKDrawing
    var isDirty: Bool
}

private struct V2RecallTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let onPencilInput: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        let baseFont = UIFont.systemFont(ofSize: 19, weight: .regular)
        let serifDescriptor = baseFont.fontDescriptor.withDesign(.serif)

        textView.delegate = context.coordinator
        textView.font = serifDescriptor.map { UIFont(descriptor: $0, size: 19) } ?? baseFont
        textView.textColor = UIColor(V2Theme.ColorRole.textPrimary)
        textView.tintColor = UIColor(V2Theme.ColorRole.primary)
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityIdentifier = "recall.textEditor"
        textView.accessibilityLabel = "回想文字"

        let pencilRecognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePencilInput(_:))
        )
        pencilRecognizer.minimumPressDuration = 0
        pencilRecognizer.allowableMovement = .greatestFiniteMagnitude
        pencilRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        pencilRecognizer.cancelsTouchesInView = true
        textView.addGestureRecognizer(pencilRecognizer)

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.text = text
        }

        if isFocused, !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        textView.resignFirstResponder()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: V2RecallTextEditor

        init(parent: V2RecallTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        @objc func handlePencilInput(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            parent.onPencilInput()
        }
    }
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
