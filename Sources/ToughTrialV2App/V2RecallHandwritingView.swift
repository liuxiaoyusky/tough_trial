import PencilKit
import SwiftUI
import UIKit

enum V2RecallCanvasTool: String, CaseIterable {
    case pen
    case marker
    case eraser

    var systemImage: String {
        switch self {
        case .pen:
            "pencil.tip"
        case .marker:
            "highlighter"
        case .eraser:
            "eraser"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .pen:
            "钢笔"
        case .marker:
            "荧光笔"
        case .eraser:
            "橡皮"
        }
    }
}

struct V2RecallHandwritingCanvas: View {
    @Binding var drawing: PKDrawing
    @Binding var selectedTool: V2RecallCanvasTool
    @Binding var inkColor: Color

    let onDrawingChanged: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            V2PencilCanvas(
                drawing: $drawing,
                selectedTool: selectedTool,
                inkColor: UIColor(inkColor),
                onDrawingChanged: onDrawingChanged
            )

            toolBar
                .padding(.bottom, 18)
        }
    }

    private var toolBar: some View {
        HStack(spacing: 4) {
            ForEach(V2RecallCanvasTool.allCases, id: \.self) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            selectedTool == tool
                                ? V2Theme.ColorRole.textInverse
                                : V2Theme.ColorRole.textSecondary
                        )
                        .frame(width: 38, height: 38)
                        .background(
                            selectedTool == tool
                                ? V2Theme.ColorRole.textPrimary
                                : Color.clear
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.accessibilityLabel)
            }

            Divider()
                .frame(height: 22)
                .padding(.horizontal, 4)

            ColorPicker("笔迹颜色", selection: $inkColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 38, height: 38)
                .accessibilityLabel("笔迹颜色")
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .background(V2Theme.ColorRole.surfaceRaised.opacity(0.94))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(V2Theme.ColorRole.outline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }
}

private struct V2PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    let selectedTool: V2RecallCanvasTool
    let inkColor: UIColor
    let onDrawingChanged: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, onDrawingChanged: onDrawingChanged)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.drawingPolicy = Self.drawingPolicy
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        canvas.keyboardDismissMode = .interactive
        canvas.isAccessibilityElement = true
        canvas.accessibilityIdentifier = "recall.handwritingCanvas"
        canvas.accessibilityLabel = "手写画布"
        updateAccessibilityValue(for: canvas)
        applyTool(to: canvas)

        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.drawing = $drawing
        context.coordinator.onDrawingChanged = onDrawingChanged
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        applyTool(to: canvas)
        updateAccessibilityValue(for: canvas)
    }

    private func applyTool(to canvas: PKCanvasView) {
        switch selectedTool {
        case .pen:
            canvas.tool = PKInkingTool(.pen, color: inkColor, width: 3)
        case .marker:
            canvas.tool = PKInkingTool(.marker, color: inkColor.withAlphaComponent(0.45), width: 16)
        case .eraser:
            canvas.tool = PKEraserTool(.vector)
        }
    }

    private func updateAccessibilityValue(for canvas: PKCanvasView) {
        canvas.accessibilityValue = canvas.drawing.strokes.isEmpty ? "空白" : "已有笔迹"
    }

    private static var drawingPolicy: PKCanvasViewDrawingPolicy {
#if targetEnvironment(simulator)
        .anyInput
#else
        UIDevice.current.userInterfaceIdiom == .phone ? .anyInput : .pencilOnly
#endif
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        var onDrawingChanged: () -> Void

        init(drawing: Binding<PKDrawing>, onDrawingChanged: @escaping () -> Void) {
            self.drawing = drawing
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
            canvasView.accessibilityValue =
                canvasView.drawing.strokes.isEmpty ? "空白" : "已有笔迹"
            onDrawingChanged()
        }
    }
}

struct V2RecallDrawingStore {
    private let fileManager: FileManager
    private let baseDirectory: URL?

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

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
        if drawing.strokes.isEmpty {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try drawing.dataRepresentation().write(to: url, options: .atomic)
    }

    private func fileURL(for date: Date) -> URL {
        let root = baseDirectory ?? (try? fileManager.url(
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
        return root
            .appendingPathComponent("ToughTrial", isDirectory: true)
            .appendingPathComponent("recall-drawings", isDirectory: true)
            .appendingPathComponent(filename)
    }
}
