import AVFoundation
import AVKit
import CoreTransferable
import PhotosUI
import SwiftUI
import ToughTrialV2Core
import UniformTypeIdentifiers

private struct V2SelectedTranscriptionVideo: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-video-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

struct V2TranscriptionView: View {
    @Binding private var incomingURL: URL?
    @StateObject private var store: V2TranscriptionStore
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var importing = false
    @State private var selectedVideo: PhotosPickerItem?
    @State private var importingMedia = false
    @State private var issue: String?

    private var filteredRecords: [V2TranscriptionRecord] { store.records.filter { $0.matches(query) } }

    init(directory: URL? = nil, incomingURL: Binding<URL?> = .constant(nil)) {
        _incomingURL = incomingURL
        let store = V2TranscriptionStore(directory: directory)
        #if DEBUG
        // Isolated UI fixtures use real local WAV data and persistence, never service credentials.
        if ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TESTING"] == "1",
           let fixture = ProcessInfo.processInfo.environment["TOUGH_TRIAL_UI_TEST_TRANSCRIPTION"] {
            let record = V2TranscriptionRecord(title: "转录测试录音", source: .audio, mediaFileName: "fixture.wav",
                status: fixture == "processing" ? .processing : fixture == "complete" ? .complete : .draft,
                transcript: fixture == "draft" ? "" : "这是本机保存的测试逐字稿。",
                summary: fixture == "draft" ? nil : "测试摘要")
            if let wav = try? V2RecordedSpeechClient.wavData(pcm: Data(repeating: 0, count: 32_000)) {
                try? wav.write(to: store.mediaURL(for: record))
                try? store.update(record)
            }
        }
        #endif
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    importActions
                    if let message = store.issue ?? issue {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(V2Theme.orange)
                            .accessibilityIdentifier("transcription.issue")
                    }
                    if importingMedia { ProgressView("正在保存原文件…") }
                    if store.records.isEmpty {
                        ContentUnavailableView("把声音留成可查的文字", systemImage: "waveform",
                            description: Text("导入语音备忘录或相册视频，转录后就能按内容搜索。"))
                            .frame(maxWidth: .infinity, minHeight: 330)
                    } else if filteredRecords.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredRecords) { record in
                                NavigationLink(value: record.id) {
                                    recordRow(record)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("transcription.open.\(record.id)")
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(V2Theme.page)
            .foregroundStyle(V2Theme.ink)
            .navigationTitle("转录")
            .searchable(text: $query, prompt: "搜索文件名、摘要或逐字稿")
            .navigationDestination(for: UUID.self) { id in
                V2TranscriptionDetailView(store: store, recordID: id)
            }
            .onAppear { importIncomingFile() }
            .onChange(of: incomingURL) { _, _ in importIncomingFile() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: false) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    let type = UTType(filenameExtension: url.pathExtension)
                    importMedia(url, source: type?.conforms(to: .movie) == true ? .video : .audio)
                case let .failure(error): issue = error.localizedDescription
                }
            }
            .onChange(of: selectedVideo) { _, item in
                guard let item else { return }
                Task {
                    defer { selectedVideo = nil }
                    do {
                        guard let video = try await item.loadTransferable(type: V2SelectedTranscriptionVideo.self) else {
                            throw V2TranscriptionProcessingError.noAudio
                        }
                        defer { try? FileManager.default.removeItem(at: video.url) }
                        await importMedia(video.url, source: .video)
                    } catch { issue = error.localizedDescription }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var importActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建转录").font(.headline)
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    Label("相册视频", systemImage: "video")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("transcription.import.photos")
                Button { importing = true } label: {
                    Label("文件录音或视频", systemImage: "doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("transcription.import.files")
            }
            .disabled(importingMedia)
            Text("语音备忘录可从“分享 → 在 Tough Trial 中打开”导入；若未显示，也可先存到“文件”。")
                .font(.caption).foregroundStyle(V2Theme.secondary)
        }
        .padding(16)
        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func recordRow(_ record: V2TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: record.source == .video ? "video.fill" : "waveform")
                    .foregroundStyle(V2Theme.blue)
                Text(record.title).font(.headline).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(V2Theme.tertiary)
            }
            if !record.preview.isEmpty {
                Text(record.preview).font(.subheadline).foregroundStyle(V2Theme.secondary).lineLimit(2)
            }
            Text("\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(record.provider == .apple ? "苹果原生" : record.provider == .funASR ? "FunASR" : "未开始") · \(statusLabel(record.status))")
                .font(.caption).foregroundStyle(V2Theme.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func statusLabel(_ status: V2TranscriptionRecord.Status) -> String {
        switch status {
        case .draft: "待转录"
        case .processing: "正在转录"
        case .failed: "可继续"
        case .complete: "已完成"
        }
    }

    private func importMedia(_ url: URL, source: V2TranscriptionRecord.Source) {
        Task { await importMedia(url, source: source) }
    }

    private func importIncomingFile() {
        guard let url = incomingURL else { return }
        incomingURL = nil
        let type = UTType(filenameExtension: url.pathExtension)
        importMedia(url, source: type?.conforms(to: .movie) == true ? .video : .audio)
    }

    private func importMedia(_ url: URL, source: V2TranscriptionRecord.Source) async {
        importingMedia = true
        defer { importingMedia = false }
        do {
            let record = try await store.importMedia(from: url, source: source)
            issue = nil
            path.append(record.id)
        } catch { issue = error.localizedDescription }
    }
}

private struct V2TranscriptionDetailView: View {
    @ObservedObject var store: V2TranscriptionStore
    @ObservedObject private var plugins = V2PluginStore.shared
    let recordID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var provider: V2TranscriptionRecord.Provider
    @State private var activeTask: Task<Void, Never>?
    @State private var processingStage = "正在准备转录…"
    @State private var generatingSummary = false
    @State private var issue: String?
    @State private var editingSummary = false
    @State private var editedSummary = ""
    @State private var confirmingDelete = false

    init(store: V2TranscriptionStore, recordID: UUID) {
        self.store = store
        self.recordID = recordID
        _provider = State(initialValue: store.record(recordID)?.provider
            ?? (V2SpeechSettings.provider == .apple ? .apple : .funASR))
    }

    private var record: V2TranscriptionRecord? { store.record(recordID) }

    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 22) {
                    Text(record.title).font(V2Theme.TypeRole.headlineMedium)
                        .foregroundStyle(V2Theme.ink)
                    Text("\(record.source == .video ? "相册或文件视频" : "录音文件") · \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(V2Theme.secondary)
                    if record.status != .complete { preparation(record) }
                    if let message = issue ?? record.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(V2Theme.orange)
                            .accessibilityIdentifier("transcription.issue")
                    }
                    summarySection(record)
                    transcriptSection(record)
                }
                .padding(20)
            }
        }
        .background(V2Theme.page)
        .foregroundStyle(V2Theme.ink)
        .v2InlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("删除记录与原文件", role: .destructive) { confirmingDelete = true }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityIdentifier("transcription.record.menu")
            }
        }
        .confirmationDialog("删除这条转录记录及本机原文件？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive) {
                do { activeTask?.cancel(); try store.delete(recordID); dismiss() }
                catch { issue = error.localizedDescription }
            }
            Button("取消", role: .cancel) { }
        }
        .sheet(isPresented: $editingSummary) {
            NavigationStack {
                TextEditor(text: $editedSummary).padding()
                    .accessibilityIdentifier("transcription.summary.input")
                    .navigationTitle("编辑摘要")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { editingSummary = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                guard var current = record else { return }
                                current.summary = editedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                                do { try store.update(current); issue = nil; editingSummary = false }
                                catch { issue = error.localizedDescription }
                            }
                        }
                    }
            }
        }
        .onDisappear { activeTask?.cancel() }
        .onChange(of: plugins.disabled) { _, _ in if !plugins.enabled("transcription") { activeTask?.cancel() } }
    }

    private func preparation(_ record: V2TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(record.status == .processing ? "正在转录" : "准备转录").font(.headline)
            Picker("识别方式", selection: $provider) {
                Text("苹果原生").tag(V2TranscriptionRecord.Provider.apple)
                Text("FunASR 云端").tag(V2TranscriptionRecord.Provider.funASR)
            }
            .pickerStyle(.segmented)
            .disabled(record.status == .processing)
            .accessibilityIdentifier("transcription.provider")
            Text(provider == .apple
                ? "音频在本机识别。需要 iOS 26 / macOS 26 和中文语音模型。"
                : "只上传音轨到阿里云百炼，不上传视频画面；每段最多 5 分钟，按服务用量计费。")
                .font(.subheadline).foregroundStyle(V2Theme.secondary)
            if record.status == .failed, provider == .apple, !record.transcript.isEmpty {
                Text("苹果原生重试会重新识别整段，并用新结果替换已保存的部分文字。")
                    .font(.caption).foregroundStyle(V2Theme.secondary)
            }
            Text("转录完成后，若已配置 AI 服务，逐字稿会发送给该服务生成摘要；原文件和记录留在本机。")
                .font(.caption).foregroundStyle(V2Theme.secondary)
            if record.status == .processing {
                ProgressView(processingStage)
                    .tint(V2Theme.blue)
                    .accessibilityIdentifier("transcription.progress")
                Button("暂停，稍后继续") { activeTask?.cancel() }
                    .foregroundStyle(V2Theme.blue)
                    .accessibilityIdentifier("transcription.pause")
            } else {
                Button(record.status == .failed ? "继续转录" : "开始转录") { start(record) }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("transcription.start")
                NavigationLink("打开语音设置") { V2SpeechSettingsView() }
                    .foregroundStyle(V2Theme.blue)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func summarySection(_ record: V2TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("自动摘要").font(.title3.bold())
                Spacer()
                if record.summary != nil {
                    Button("编辑") { editedSummary = record.summary ?? ""; editingSummary = true }
                        .disabled(record.status == .processing || generatingSummary)
                        .accessibilityIdentifier("transcription.summary.edit")
                }
            }
            if let summary = record.summary, !summary.isEmpty {
                Text(summary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(record.transcript.isEmpty ? "转录完成后显示摘要。" : "摘要尚未生成；完整逐字稿已经保存。")
                    .foregroundStyle(V2Theme.secondary)
            }
            if !record.transcript.isEmpty {
                Button(generatingSummary ? "正在生成摘要…" : "重新生成摘要") { summarize(record) }
                    .disabled(record.status == .processing || generatingSummary)
                    .foregroundStyle(V2Theme.blue)
                    .accessibilityIdentifier("transcription.summary.retry")
            }
            if record.status == .processing {
                Text("转录中暂时无法编辑；暂停后可以修改已保存的内容。")
                    .font(.caption).foregroundStyle(V2Theme.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func transcriptSection(_ record: V2TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("逐字稿").font(.title3.bold())
            if record.transcript.isEmpty {
                Text("原文件已保存，等待转录。")
                    .foregroundStyle(V2Theme.secondary)
            } else {
                Text(record.transcript).lineLimit(3).foregroundStyle(V2Theme.secondary)
            }
            NavigationLink("查看全文与播放原文件") {
                V2TranscriptionTextView(store: store, recordID: recordID)
            }
            .accessibilityIdentifier("transcription.transcript.open")
            .foregroundStyle(V2Theme.blue)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V2Theme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func start(_ record: V2TranscriptionRecord) {
        do {
            let ticket = try plugins.ticket(["transcription"])
            var current = record
            current.status = .processing
            current.errorMessage = nil
            try store.update(current)
            issue = nil
            processingStage = "正在准备转录…"
            activeTask?.cancel()
            let selectedProvider = provider
            activeTask = Task {
                do {
                    try await V2TranscriptionProcessor.transcribe(current, store: store, provider: selectedProvider) {
                        processingStage = $0
                    }
                    try Task.checkCancellation()
                    try plugins.validate(ticket)
                    guard var finished = store.record(recordID) else { return }
                    finished.status = .complete
                    try store.update(finished)
                    summarize(finished)
                } catch {
                    guard var failed = store.record(recordID), failed.status == .processing else { return }
                    failed.status = .failed
                    failed.errorMessage = V2TranscriptionProcessor.failureMessage(error, stage: processingStage,
                        cancelled: Task.isCancelled)
                    do { try store.update(failed) }
                    catch { issue = error.localizedDescription }
                }
            }
        } catch { issue = error.localizedDescription }
    }

    private func summarize(_ record: V2TranscriptionRecord) {
        generatingSummary = true
        Task {
            defer { generatingSummary = false }
            do {
                try await V2TranscriptionProcessor.summarize(record, store: store)
                issue = nil
            } catch { issue = error.localizedDescription }
        }
    }
}

private struct V2TranscriptionTextView: View {
    @ObservedObject var store: V2TranscriptionStore
    let recordID: UUID
    @State private var editing = false
    @State private var draft = ""
    @State private var issue: String?
    @State private var player: AVPlayer?
    @State private var playing = false

    private var record: V2TranscriptionRecord? { store.record(recordID) }

    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 16) {
                    if record.source == .video {
                        VideoPlayer(player: player)
                            .frame(height: 230)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Button(playing ? "暂停原录音" : "播放原录音", systemImage: playing ? "pause.fill" : "play.fill") {
                            if playing { player?.pause() } else { player?.play() }
                            playing.toggle()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("transcription.audio.play")
                    }
                    HStack {
                        Text("完整内容").font(.title3.bold())
                        Spacer()
                        Button("编辑文字") { draft = record.transcript; editing = true }
                            .disabled(record.status == .processing)
                            .accessibilityIdentifier("transcription.transcript.edit")
                    }
                    if let issue { Text(issue).foregroundStyle(V2Theme.orange) }
                    if record.segments.isEmpty {
                        Text(record.transcript.isEmpty ? "暂无逐字稿。" : record.transcript)
                            .textSelection(.enabled)
                    } else {
                        ForEach(Array(record.segments.enumerated()), id: \.offset) { _, segment in
                            VStack(alignment: .leading, spacing: 6) {
                                Button(formatTime(segment.start)) { player?.seek(to: CMTime(seconds: segment.start, preferredTimescale: 600)); player?.play(); playing = true }
                                    .font(.caption.bold())
                                    .accessibilityIdentifier("transcription.transcript.seek")
                                Text(segment.text).textSelection(.enabled)
                            }
                            Divider()
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(V2Theme.page)
        .navigationTitle("逐字稿")
        .onAppear {
            if let record { player = AVPlayer(url: store.mediaURL(for: record)) }
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            #endif
        }
        .onDisappear { player?.pause() }
        .sheet(isPresented: $editing) {
            NavigationStack {
                TextEditor(text: $draft).padding()
                    .accessibilityIdentifier("transcription.transcript.input")
                    .navigationTitle("编辑逐字稿")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { editing = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                guard var current = record else { return }
                                current.transcript = draft
                                current.segments = []
                                current.summary = nil
                                do { try store.update(current); issue = nil; editing = false }
                                catch { issue = error.localizedDescription }
                            }
                        }
                    }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
