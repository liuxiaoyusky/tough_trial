import AVFoundation
import PhotosUI
#if os(iOS)
import PencilKit
#endif
import SwiftUI
import ToughTrialV2Core
import Vision

struct V2CaptureView: View {
    @ObservedObject private var plugins = V2PluginStore.shared
    @Binding private var quickRequest: V2QuickCaptureRequest?
    @StateObject private var store: V2CaptureStore
    @StateObject private var speech = V2AssistantSpeechTranscriber()
    @AppStorage(V2SpeechSettings.providerKey) private var speechProvider = V2SpeechProvider.funASR
    @State private var section = 0
    @State private var photo: PhotosPickerItem?
    @State private var handwriting = false
    @State private var handwritingBlock: V2CaptureBlock?
#if os(iOS)
    @State private var drawing = PKDrawing()
#endif
    @State private var ledgerForm = false
    @State private var taskForm = false
    @State private var importForm = false
    @State private var confirmReplacement = false
    @State private var categoryEntry: V2LedgerEntry?
    @State private var isReadingImage = false
    @State private var audioPlayer: AVAudioPlayer?
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var editorFocused: Bool

    init(appStore: V2AppStore, client: (any V2CaptureClient)? = nil, quickRequest: Binding<V2QuickCaptureRequest?> = .constant(nil)) {
        _quickRequest = quickRequest
        _store = StateObject(wrappedValue: V2CaptureStore(appStore: appStore, client: client))
    }
    init(store: V2CaptureStore) {
        _quickRequest = .constant(nil)
        _store = StateObject(wrappedValue: store)
    }
    var body: some View {
        NavigationStack {
            captureContent
            .onAppear {
                #if DEBUG && os(iOS)
                if ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TEST_FINANCE"] == "1" { store.seedFinanceAttachmentFixture() }
                #endif
                store.refresh()
                speech.onRecordingCaptured = { data in try store.captureAudio(data) }
                consumeQuickRequest()
            }
            .onChange(of: plugins.disabled) { _, _ in if section == 1 && !plugins.enabled("ledger") { section = 0 }; if !plugins.enabled("speech") { speech.cancel() } }
            .onChange(of: quickRequest) { _, _ in consumeQuickRequest() }
            .onChange(of: speech.isActive) { _, _ in consumeQuickRequest() }
            .onChange(of: store.isOrganizing) { _, _ in consumeQuickRequest() }
            .onChange(of: isReadingImage) { _, _ in consumeQuickRequest() }
            .onChange(of: ledgerForm) { _, _ in consumeQuickRequest() }
            .onChange(of: taskForm) { _, _ in consumeQuickRequest() }
            .onChange(of: handwriting) { _, _ in consumeQuickRequest() }
            .onChange(of: importForm) { _, _ in consumeQuickRequest() }
            .onChange(of: categoryEntry?.id) { _, _ in consumeQuickRequest() }
            .onChange(of: confirmReplacement) { _, _ in consumeQuickRequest() }
            .onDisappear { if !store.isOrganizing { _ = store.saveDraft() }; speech.cancel(); speech.onRecordingCaptured = nil; audioPlayer?.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { _ = store.saveDraft(); speech.cancel() }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                isReadingImage = true
                Task {
                    defer { isReadingImage = false; photo = nil }
                    do {
                        let ticket = try plugins.ticket(["capture", "attachments"])
                        guard let data = try await item.loadTransferable(type: Data.self), V2Platform.isImage(data) else { throw V2CaptureError.assetUnavailable }
                        try plugins.validate(ticket)
                        store.attach(data: data, kind: .image, fileExtension: item.supportedContentTypes.first?.preferredFilenameExtension ?? "image")
                        guard store.issue == nil, let captureID = store.editingID, let revision = store.editingRevision, let block = store.mediaBlocks.last else { return }
                        let recognized = await Self.recognize(data)
                        try plugins.validate(ticket)
                        store.recognizedMedia(recognized, captureID: captureID, sourceRevision: revision, blockID: block.id, assetID: block.assetID)
                    } catch { store.issue = "图片未能保存，请重新选择。" }
                }
            }
        }
        .tint(V2Theme.blue)
    }
    private var captureContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("内容", selection: $section) {
                        Text("记录").tag(0); if plugins.enabled("ledger") { Text("记账").tag(1) }; Text("收纳").tag(2); Text("灵感").tag(3)
                    }.pickerStyle(.segmented).id(plugins.enabled("ledger")).accessibilityIdentifier("capture.sections")
                    HStack {
                        Spacer()
                        if plugins.enabled("imports") { Button("导入资料", systemImage: "square.and.arrow.down") { editorFocused = false; importForm = true }
                            .font(.subheadline).accessibilityIdentifier("capture.import")
                            .disabled(store.isOrganizing || speech.isActive || isReadingImage) }
                    }
                    switch section {
                    case 0: editor; resultList; history
                    case 1: ledger
                    case 2: inbox
                    default: notes
                    }
                    Text("仅保存在本机 · 原文与附件可回看")
                        .font(.caption).foregroundStyle(V2Theme.tertiary).frame(maxWidth: .infinity)
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .allowsHitTesting(!isReadingImage)
            .background(V2Theme.page)
            .navigationTitle("随手记")
            .toolbar {
                ToolbarItem(placement: .v2Trailing) {
                    if section == 1 {
                        NavigationLink { V2CaptureCategoriesView(store: store) } label: { Image(systemName: "folder.badge.gearshape") }
                            .accessibilityLabel("管理账单分类")
                    } else {
                        Button { store.newEntry(); section = 0 } label: { Image(systemName: "square.and.pencil") }
                            .disabled(store.isOrganizing || speech.isActive || isReadingImage).accessibilityLabel("新记录")
                    }
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起键盘") { editorFocused = false } }
                #endif
            }
            #if os(iOS)
            .v2Sheet(isPresented: $handwriting) {
                V2CaptureDrawingSheet(drawing: drawing) { value in
                    drawing = value
                    let id = handwritingBlock?.id
                    // Keep the original editable strokes; OCR is a derived representation on the same source block.
                    let data = value.dataRepresentation()
                    let rendered = value.image(from: value.bounds.insetBy(dx: -12, dy: -12), scale: 2).pngData()
                    store.attach(data: data, kind: .handwriting, fileExtension: "drawing", replacing: id)
                    guard store.issue == nil, let captureID = store.editingID, let revision = store.editingRevision,
                          let ticket = try? plugins.ticket(["capture", "attachments"]),
                          let block = id.flatMap({ id in store.mediaBlocks.first { $0.id == id } }) ?? store.mediaBlocks.last else { return }
                    isReadingImage = true
                    Task {
                        defer { isReadingImage = false }
                        let recognized = await Self.recognize(rendered)
                        guard (try? plugins.validate(ticket)) != nil else { return }
                        store.recognizedMedia(recognized, captureID: captureID, sourceRevision: revision, blockID: block.id, assetID: block.assetID)
                    }
                }
            }
            #endif
            .confirmationDialog("替换这条原文之前生成的结果？", isPresented: $confirmReplacement, titleVisibility: .visible) {
                Button("确认替换为新结果") { if let batch = store.activeBatch { store.replaceResults(batch) } }
            } message: { Text("将先撤回下方列出的旧结果，再保存新结果。已有后续修改时整组操作会停止；新账单的类别仍需确认。") }
            .v2Sheet(isPresented: $taskForm) { V2QuickTaskForm(store: store) }
            .v2Sheet(isPresented: $importForm) { V2ExternalImportView(captureStore: store, onOrganize: { section = 0 }) }
            .v2Sheet(isPresented: $ledgerForm) { V2CaptureLedgerForm(store: store) }
            .v2Sheet(item: $categoryEntry) { entry in V2CaptureCategorySheet(store: store, entry: entry) }
            .alert("暂未完成", isPresented: Binding(get: { !ledgerForm && store.issue != nil }, set: { if !$0 && !ledgerForm { store.issue = nil } })) {
                Button("知道了") { store.issue = nil }
            } message: { Text(store.issue ?? "") }
    }
    private func consumeQuickRequest() {
        guard let request = quickRequest else { return }
        guard !store.isOrganizing, !speech.isActive, !isReadingImage, !handwriting, !ledgerForm, !taskForm, !importForm, categoryEntry == nil, !confirmReplacement else {
            store.message = "已保留最近点击的快捷入口，完成当前输入后打开。"; return
        }
        guard store.newEntry() else { return }
        quickRequest = nil
        switch request.action {
        case .ledger: section = 1; ledgerForm = true
        case .task: section = 0; taskForm = true
        case .note: section = 0; editorFocused = true
        }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("想到什么，就记下来。")
                .font(V2Theme.TypeRole.titleLarge)
            Text("账单、复盘、灵感和待办，可以写在一起。")
                .font(.subheadline).foregroundStyle(V2Theme.secondary)
            ZStack(alignment: .topLeading) {
                if store.draft.isEmpty {
                    Text("比如：午餐花了 38 元人民币。今天沟通很顺畅，下次先列出重点。还想拍一期早餐视频……")
                        .font(.body).foregroundStyle(V2Theme.tertiary).padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $store.draft).frame(minHeight: 150).scrollContentBackground(.hidden)
                    .focused($editorFocused).accessibilityIdentifier("capture.input")
                    .disabled(store.isOrganizing || speech.isActive)
            }
            ForEach(store.mediaBlocks) { block in mediaRow(block) }
            if plugins.enabled("attachments") { HStack(spacing: 20) {
                PhotosPicker(selection: $photo, matching: .images) { Label("图片", systemImage: "photo") }
                #if os(iOS)
                Button { drawing = PKDrawing(); handwritingBlock = nil; handwriting = true } label: { Label("手写", systemImage: "pencil.tip") }
                #endif
                Spacer()
                if isReadingImage { ProgressView() }
            }.font(.subheadline).disabled(store.isOrganizing || speech.isActive || isReadingImage)
                V2FileAttachmentPicker { files in store.attachFiles(files) }
                    .disabled(store.isOrganizing || speech.isActive || isReadingImage)
            }
            Divider()
            if plugins.enabled("speech") { HStack {
                Picker("听写方式", selection: $speechProvider) {
                    ForEach(V2SpeechProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).labelsHidden().disabled(speech.isActive)
                Spacer()
                if speech.isActive {
                    Button("放弃", role: .cancel) { speech.cancel() }
                    Button(speech.canRetry ? "重试转写" : "完成录音") {
                        speech.finish { text in
                            store.draft += (store.draft.isEmpty ? "" : "\n") + text
                            _ = store.saveDraft()
                        }
                    }.disabled(speech.state == .connecting || speech.state == .finishing)
                } else {
                    Button { speech.start(provider: speechProvider, key: (try? V2SpeechSettings.loadKey()) ?? "", ownerModuleID: "core.capture") }
                        label: { Label("说一段", systemImage: "mic") }
                        .disabled(store.isOrganizing)
                }
            }.font(.subheadline)
            Text(speechProvider == .apple ? "苹果听写保留文字" : "完成后转写 · 原始录音保存在本机")
                .font(.caption2).foregroundStyle(V2Theme.tertiary)
            if !speech.status.isEmpty { Text(speech.status).font(.caption).foregroundStyle(V2Theme.secondary) }
            if let error = speech.errorMessage { Text(error).font(.caption).foregroundStyle(V2Theme.orange) }
            }
            HStack {
                Button("保存原文") {
                    editorFocused = false
                    if store.saveDraft() != nil { store.message = "原文已保存" }
                }.disabled(store.isOrganizing || speech.isActive)
                Spacer()
                if store.isOrganizing {
                    ProgressView()
                    Button("停止整理") { store.cancel() }
                } else {
                    Button { editorFocused = false; store.organize() } label: { Label("整理", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("capture.organize")
                        .disabled(!plugins.enabled("assistant") || speech.isActive || isReadingImage || (store.draft.isEmpty && store.mediaBlocks.isEmpty))
                }
            }
            if store.isOrganizing {
                Text("正在拆分内容和核对格式 · \(store.modelLabel)").font(.caption).foregroundStyle(V2Theme.secondary)
            }
            if let message = store.message { Text(message).font(.caption).foregroundStyle(V2Theme.secondary) }
        }.padding(18).background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 20))
    }
    @ViewBuilder private func mediaRow(_ block: V2CaptureBlock) -> some View {
        if let asset = store.asset(for: block) {
            VStack(alignment: .leading, spacing: 8) {
                if block.kind == .document || block.kind == .image { V2AttachmentTile(asset: asset, store: store.assets) }
                if block.kind == .handwriting || block.kind == .audio { HStack {
                    Label(block.kind == .handwriting ? "手写原稿" : block.kind == .audio ? "原始录音" : "图片原件",
                          systemImage: block.kind == .handwriting ? "pencil.tip" : block.kind == .audio ? "waveform" : "photo")
                    Spacer()
                    if block.kind == .handwriting {
                        #if os(iOS)
                        Button("继续写") {
                            guard let data = try? store.assets.data(for: asset), let saved = try? PKDrawing(data: data) else { store.issue = "手写原稿无法读取"; return }
                            drawing = saved; handwritingBlock = block; handwriting = true
                        }
                        #endif
                    }
                    if block.kind == .audio {
                        Button("播放") {
                            do {
                                #if os(iOS)
                                try AVAudioSession.sharedInstance().setCategory(.playback)
                                try AVAudioSession.sharedInstance().setActive(true)
                                #endif
                                audioPlayer = try AVAudioPlayer(data: store.assets.data(for: asset)); audioPlayer?.play()
                            }
                            catch { store.issue = "录音无法播放。" }
                        }.disabled(speech.isActive)
                    }
                    if let url = try? store.assets.url(for: asset) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                }.font(.caption) }
                Text(block.kind == .audio ? "录音原件已保存" : block.text?.isEmpty == false ? "本机识别：\(block.text!)" : "原件已保存 · 暂无识别文字")
                    .font(.caption).foregroundStyle(V2Theme.secondary).textSelection(.enabled)
            }
        }
    }
    @ViewBuilder private var resultList: some View {
        if let batch = store.activeBatch {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("整理去向").font(.headline)
                    Spacer()
                    Text("\(batch.proposal.items.count) 项").font(.caption).foregroundStyle(V2Theme.secondary)
                }
                if store.hasEarlierResults(batch) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("将替换的旧结果").font(.subheadline.bold())
                        ForEach(store.earlierReceipts(batch)) { receipt in
                            if let old = store.state.batches.first(where: { $0.id == receipt.batchID })?.proposal.items.first(where: { $0.id == receipt.candidateID }) {
                                Text("\(old.kind.label) · \(old.payload.text) \(old.payload.currency ?? "") \(old.payload.amount ?? "")").font(.caption)
                            }
                        }
                        Button("核对下方新结果并替换") { confirmReplacement = true }.font(.subheadline)
                    }.padding(14).background(V2Theme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }
                ForEach(batch.proposal.items) { item in
                    let receipt = store.receipt(for: item, batch: batch)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(item.kind.label).font(.subheadline.bold())
                            Spacer()
                            Text(receipt?.status.label ?? "待确认保存").font(.caption)
                                .foregroundStyle(receipt?.status == .applied ? V2Theme.mint : V2Theme.orange)
                        }
                        if item.kind == .ledger {
                            Text("\(item.payload.currency ?? "币种待补充") \(item.payload.amount ?? "金额待补充")")
                                .font(.title3.bold().monospacedDigit())
                        }
                        Text(item.payload.text).font(.body).textSelection(.enabled)
                        if let error = receipt?.error { Text(error.localizedDescription).font(.caption).foregroundStyle(V2Theme.orange) }
                        if let receipt {
                            if receipt.status != .undone && receipt.status != .rejected {
                                HStack {
                                    if let ledger = store.state.ledger.first(where: { $0.id == receipt.targetID }) {
                                        Button(ledger.categoryID == "others" ? "确认分类" : "调整分类") { categoryEntry = ledger }
                                            .accessibilityIdentifier("capture.confirmCategory")
                                    }
                                    Spacer()
                                    Button("撤销") { store.undo(receipt) }.accessibilityIdentifier("capture.undo.\(item.id)")
                                }.font(.subheadline)
                            }
                        } else if !store.hasEarlierResults(batch) {
                            HStack {
                                Button("确认保存") { store.apply(item, batch: batch) }
                                Spacer(); Button("跳过") { store.reject(item, batch: batch) }
                            }.font(.subheadline)
                        }
                        DisclosureGroup("来源与整理记录") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, evidence in Text(evidence.quote).font(.caption) }
                                Text("原文版本 \(batch.proposal.sourceRevision) · \(batch.model)")
                                Text("Trace \(batch.traceID)").textSelection(.enabled)
                                if let receipt { Text("回执 \(receipt.id)").textSelection(.enabled) }
                            }.font(.caption2).foregroundStyle(V2Theme.secondary)
                        }.font(.caption)
                    }.padding(16).background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 16))
                        .onAppear { store.presented(item, batch: batch) }
                        .onChange(of: receipt?.status) { _, _ in store.presented(item, batch: batch) }
                }
            }.id("capture.results")
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("原始记录").font(.headline)
            if store.state.latestEntries.isEmpty { Text("先留住想法，整理可以稍后再做。").foregroundStyle(V2Theme.secondary) }
            ForEach(store.state.latestEntries) { entry in
                Button { store.open(entry); editorFocused = false } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.text.isEmpty ? "附件记录" : entry.text).lineLimit(3).foregroundStyle(V2Theme.ink)
                        Text(entry.recordedAt, style: .date).font(.caption).foregroundStyle(V2Theme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).disabled(store.isOrganizing || speech.isActive)
            }
        }
    }
    private var ledger: some View {
        V2LedgerList(store: store, onAdd: { ledgerForm = true },
                     onCategory: { categoryEntry = $0 }, onSource: { openSource(receiptID: $0) })
    }
    private var inbox: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Others · 等你理一理").font(.title2.bold())
            Text("无法归类、待补充和账单待确认，都留在这里。").font(.subheadline).foregroundStyle(V2Theme.secondary)
            ForEach(store.state.receipts.filter { $0.status == .needsInformation || $0.status == .needsConfirmation || $0.status == .failed }) { receipt in
                Button { openSource(receiptID: receipt.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.state.batches.first { $0.id == receipt.batchID }?.proposal.items.first { $0.id == receipt.candidateID }?.payload.text ?? "待整理内容")
                        Text(receipt.error?.localizedDescription ?? receipt.status.label).font(.caption).foregroundStyle(V2Theme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
            ForEach(store.state.notes.filter { $0.kind == .other }.reversed()) { note in
                V2CaptureNoteCard(note: note, source: store.noteSource(receiptID: note.receiptID))
            }
            ForEach(store.state.latestEntries.filter { entry in !store.state.batches.contains { $0.proposal.captureID == entry.id } }) { entry in
                Button { store.open(entry); section = 0 } label: { Label(entry.text.isEmpty ? "附件待识别" : entry.text, systemImage: "tray").lineLimit(3) }
            }
        }
    }
    private var notes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("灵感与以后想做").font(.title2.bold())
            Text("先保存可能性，不急着变成必须完成的任务。").font(.subheadline).foregroundStyle(V2Theme.secondary)
            ForEach(store.state.notes.filter { $0.kind != .other }.reversed()) { note in
                V2CaptureNoteCard(note: note, source: store.noteSource(receiptID: note.receiptID),
                    openSource: store.state.receipts.contains(where: { $0.id == note.receiptID }) ? { openSource(receiptID: note.receiptID) } : nil)
            }
        }
    }
    private func openSource(receiptID: String) {
        guard let receipt = store.state.receipts.first(where: { $0.id == receiptID }),
              let batch = store.state.batches.first(where: { $0.id == receipt.batchID }),
              let entry = store.state.latestEntries.first(where: { $0.id == batch.proposal.captureID }) else { return }
        store.open(entry); store.activeBatchID = batch.id; section = 0
    }
    nonisolated static func recognize(_ data: Data?) async -> String? {
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(data: data).perform([request])
                let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                return text.isEmpty ? nil : text
            } catch { return nil }
        }.value
    }
}

#if os(iOS)
private struct V2CaptureDrawingSheet: View {
    @State var drawing: PKDrawing
    @State private var tool = V2RecallCanvasTool.pen
    @State private var ink = Color.black
    @Environment(\.dismiss) private var dismiss
    let save: (PKDrawing) -> Void
    var body: some View {
        NavigationStack {
            V2RecallHandwritingCanvas(drawing: $drawing, selectedTool: $tool, inkColor: $ink, onDrawingChanged: {})
                .background(V2Theme.page).navigationTitle("随手写")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存原稿") { save(drawing); dismiss() }.disabled(drawing.strokes.isEmpty) }
                }
        }
    }
}

#endif

struct V2CaptureCategorySheet: View {
    @ObservedObject var store: V2CaptureStore
    let entry: V2LedgerEntry
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(entry.text); Text("\(entry.currency) \(entry.amount)").font(.title2.bold()) }
                Section("确认后才会更新账单分类") {
                    TextField("分类名称", text: $name).accessibilityIdentifier("capture.categoryName")
                    ForEach(store.state.categories.filter { $0.mergedIntoID == nil && $0.id != "others" }) { category in
                        Button(category.name) { name = category.name }
                    }
                }
                Section {
                    Button("确认分类") { store.confirmCategory(entry, name: name); if store.issue == nil { dismiss() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("capture.categorySave")
                    Button("暂不分类") { dismiss() }
                        .accessibilityIdentifier("capture.categoryReject")
                }
            }.navigationTitle("账单分类")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("稍后") { dismiss() } } }
                .onAppear {
                    if entry.categoryID != "others" { name = store.state.categories.first { $0.id == entry.categoryID }?.name ?? "" }
                    else if let receipt = store.state.receipts.first(where: { $0.id == entry.receiptID }),
                            let batch = store.state.batches.first(where: { $0.id == receipt.batchID }) {
                        name = batch.effectiveCandidate(for: receipt.candidateID)?.payload.categoryName ?? ""
                    }
                }
        }
    }
}
