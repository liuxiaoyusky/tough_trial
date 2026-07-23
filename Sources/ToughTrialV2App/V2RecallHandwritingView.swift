import PencilKit
import SwiftUI

struct V2RecallHandwritingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drawing: PKDrawing
    @State private var errorMessage: String?

    private let date: Date
    private let drawingStore: V2RecallDrawingStore

    init(date: Date) {
        self.date = date
        let drawingStore = V2RecallDrawingStore()
        self.drawingStore = drawingStore
        _drawing = State(initialValue: drawingStore.load(for: date))
    }

    var body: some View {
        NavigationStack {
            V2PencilCanvas(drawing: $drawing)
                .background(V2Theme.ColorRole.surface)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(Self.titleFormatter.string(from: date))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            dismiss()
                        }
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            drawing = PKDrawing()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("清空手写")

                        Button("保存") {
                            save()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .alert("手写稿未保存", isPresented: errorBinding) {
            Button("知道了") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "请稍后再试。")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )
    }

    private func save() {
        do {
            try drawingStore.save(drawing, for: date)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日手写"
        return formatter
    }()
}

private struct V2PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true

        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)

        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.drawing = $drawing
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        var toolPicker: PKToolPicker?

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}

private struct V2RecallDrawingStore {
    private let fileManager = FileManager.default

    func load(for date: Date) -> PKDrawing {
        guard let data = try? Data(contentsOf: fileURL(for: date)),
              let drawing = try? PKDrawing(data: data)
        else {
            return PKDrawing()
        }
        return drawing
    }

    func save(_ drawing: PKDrawing, for date: Date) throws {
        let url = fileURL(for: date)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try drawing.dataRepresentation().write(to: url, options: .atomic)
    }

    private func fileURL(for date: Date) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let filename = String(
            format: "%04d-%02d-%02d.drawing",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return base
            .appendingPathComponent("ToughTrial", isDirectory: true)
            .appendingPathComponent("recall-drawings", isDirectory: true)
            .appendingPathComponent(filename)
    }
}
