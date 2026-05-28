import SwiftUI
import ToughTrialV2Core

struct V2RecallView: View {
    @ObservedObject var store: V2AppStore
    @State private var selectedDate = "今天"
    @State private var selectedReferenceKind = V2RecallReference.Kind.event
    @State private var saveStatus = ""

    private let dates = ["今天", "昨天", "周二", "周一"]

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 760

            VStack(alignment: .leading, spacing: 18) {
                header

                if isWide {
                    HStack(alignment: .top, spacing: store.state.isRecallFullscreen ? 22 : 18) {
                        dateRail(isCompact: false)
                        editorArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !store.state.isRecallFullscreen {
                            referenceWindow
                                .frame(width: 250)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        dateRail(isCompact: true)
                        editorArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !store.state.isRecallFullscreen {
                            referenceWindow
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }

                bottomActions
            }
            .padding(.horizontal, isWide ? 28 : 18)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: store.state.isRecallFullscreen)
            .onChange(of: selectedDate) { _, _ in
                saveStatus = ""
            }
            .v2ScreenBackground()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                store.state.toggleRecallFullscreen()
            } label: {
                Image(systemName: store.state.isRecallFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(V2Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(V2Theme.panel)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(V2Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.state.isRecallFullscreen ? "退出沉浸回想" : "进入沉浸回想")

            VStack(alignment: .leading, spacing: 3) {
                Text("回想")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(V2Theme.ink)
                Text(selectedDate)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(V2Theme.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var editorArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate == "今天" ? "今天发生了什么" : "\(selectedDate)发生了什么")
                .font(.headline.weight(.semibold))
                .foregroundStyle(V2Theme.ink)

            ZStack(alignment: .topLeading) {
                TextEditor(text: recallDraftBinding)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(V2Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, -5)
                    .padding(.vertical, -7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.clear)

                if currentRecallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("写下\(selectedDate)真正发生了什么...")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(V2Theme.tertiary)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: store.state.isRecallFullscreen ? 460 : 330, maxHeight: .infinity)
        }
    }

    private var referenceWindow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("引用")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(V2Theme.ink)
                Spacer()
                Text("\(filteredReferences.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(V2Theme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(V2Theme.page)
                    .clipShape(Capsule())
            }

            kindPicker

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(filteredReferences, id: \.id) { reference in
                        RecallReferenceRow(
                            reference: reference,
                            isSelected: store.state.selectedRecallReferenceIDs(for: selectedDate).contains(reference.id)
                        ) {
                            store.state.insertRecallReference(reference.id, for: selectedDate)
                            saveStatus = ""
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(V2Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.line, lineWidth: 1)
        )
    }

    private var kindPicker: some View {
        HStack(spacing: 6) {
            ForEach(V2RecallReference.Kind.allCasesForRecallView, id: \.self) { kind in
                Button {
                    selectedReferenceKind = kind
                } label: {
                    Text(kind.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedReferenceKind == kind ? .white : V2Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedReferenceKind == kind ? V2Theme.blue : V2Theme.page)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 10) {
            if store.state.isRecallFullscreen {
                Button {
                    store.state.toggleRecallFullscreen()
                } label: {
                    Label("引用", systemImage: "quote.opening")
                }
                .buttonStyle(RecallActionButtonStyle(isPrimary: false))
            }

            Button {
                organizeDraft()
            } label: {
                Label("整理草稿", systemImage: "sparkles")
            }
            .buttonStyle(RecallActionButtonStyle(isPrimary: false))

            Button {
                store.state.applyRecallDraft(for: selectedDate)
                saveStatus = "已保存"
            } label: {
                Label("保存", systemImage: "checkmark")
            }
            .buttonStyle(RecallActionButtonStyle(isPrimary: true))

            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(V2Theme.mint)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private func dateRail(isCompact: Bool) -> some View {
        let stack = isCompact ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))

        return stack {
            ForEach(dates, id: \.self) { date in
                Button {
                    selectedDate = date
                } label: {
                    Text(date)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedDate == date ? .white : V2Theme.secondary)
                        .frame(width: isCompact ? nil : 54, height: 36)
                        .frame(maxWidth: isCompact ? .infinity : nil)
                        .background(selectedDate == date ? V2Theme.ink : V2Theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedDate == date ? Color.clear : V2Theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recallDraftBinding: Binding<String> {
        Binding(
            get: { store.state.recallDraft(for: selectedDate) },
            set: {
                store.state.setRecallDraft($0, for: selectedDate)
                saveStatus = ""
            }
        )
    }

    private var filteredReferences: [V2RecallReference] {
        store.state.recallReferences.filter { $0.kind == selectedReferenceKind }
    }

    private func organizeDraft() {
        let trimmed = currentRecallDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            store.state.setRecallDraft("\(selectedDate)真正发生的是：", for: selectedDate)
        } else if !trimmed.contains("整理：") {
            store.state.setRecallDraft("\(currentRecallDraft)\n\n整理：事实先保留，下一步再判断原因。", for: selectedDate)
        }

        saveStatus = "已整理"
    }

    private var currentRecallDraft: String {
        store.state.recallDraft(for: selectedDate)
    }
}

private struct RecallReferenceRow: View {
    let reference: V2RecallReference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(reference.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(V2Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(V2Theme.mint)
                    }
                }

                Text(reference.detail)
                    .font(.caption)
                    .foregroundStyle(V2Theme.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? V2Theme.mint.opacity(0.08) : V2Theme.page)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? V2Theme.mint.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("插入引用 \(reference.title)")
    }
}

private struct RecallActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(isPrimary ? .white : V2Theme.ink)
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(isPrimary ? V2Theme.blue : V2Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isPrimary ? Color.clear : V2Theme.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private extension V2RecallReference.Kind {
    static let allCasesForRecallView: [V2RecallReference.Kind] = [.event, .deviation, .past]

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
