// SpreadPaper/Views/EditorCanvasView.swift

import SwiftUI
import PhosphorSwift

/// Scaled preview of the display layout with the draggable, snapping image laid over it.
/// Doubles as the drop zone for new images.
struct EditorCanvasView: View {
    let selectedImage: NSImage?
    @Binding var imageOffset: CGSize
    @Binding var imageScale: CGFloat
    @Binding var isFlipped: Bool
    let manager: WallpaperManager
    let onSelectImage: () -> Void
    /// Receives dropped file URLs already narrowed to images.
    let onDropImages: ([URL]) -> Void
    @Binding var currentPreviewScale: CGFloat

    @State private var dragStartOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isDropTargeted = false
    @FocusState private var isCanvasFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let previewScale = calculatePreviewScale(geo: geo)
            let _ = updatePreviewScale(previewScale)
            let bounds = manager.previewBounds
            let canvasWidth = bounds.width * previewScale
            let canvasHeight = bounds.height * previewScale
            // The image is centred on the render canvas, which sits inside the bezel bounds.
            let centerShift = CGSize(
                width: (manager.totalCanvas.midX - bounds.midX) * previewScale,
                height: (bounds.midY - manager.totalCanvas.midY) * previewScale
            )

            ZStack {
                // Image layer
                if let img = selectedImage {
                    let pixelSize = img.pixelSize
                    let imageWidth = pixelSize.width * previewScale * imageScale
                    let imageHeight = pixelSize.height * previewScale * imageScale
                    let horizontalTiles = max(1, Int(ceil(canvasWidth / max(imageWidth, 1))) + 1)
                    ZStack {
                        ForEach(-horizontalTiles...horizontalTiles, id: \.self) { column in
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
                                .frame(width: imageWidth, height: imageHeight)
                                .offset(
                                    x: imageOffset.width + centerShift.width + CGFloat(column) * imageWidth,
                                    y: imageOffset.height + centerShift.height
                                )
                        }

                        Rectangle()
                            .stroke(
                                Color.cdAccent.opacity(0.55),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                            .frame(width: imageWidth, height: imageHeight)
                            .offset(
                                x: imageOffset.width + centerShift.width,
                                y: imageOffset.height + centerShift.height
                            )
                    }
                        .frame(width: canvasWidth, height: canvasHeight)
                        .contentShape(Rectangle())
                        .opacity(isDragging ? 0.7 : 1.0)
                        .highPriorityGesture(
                            DragGesture()
                                .onChanged { value in
                                    isDragging = true
                                    let raw = CGSize(
                                        width: dragStartOffset.width + value.translation.width,
                                        height: dragStartOffset.height + value.translation.height
                                    )
                                    imageOffset = calculateSnapping(
                                        raw: raw,
                                        imgSize: pixelSize,
                                        canvasSize: manager.totalCanvas.size,
                                        previewScale: previewScale,
                                        zoomScale: imageScale
                                    )
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    dragStartOffset = imageOffset
                                }
                        )
                } else {
                    // Drop zone
                    VStack(spacing: 12) {
                        Ph.fileArrowDown.regular
                            .cdIcon(Color.cdTextTertiary, size: 32)
                        Text("Drop image here")
                            .font(.cd(.callout))
                            .foregroundStyle(Color.cdTextSecondary)
                        Button("Browse Files", action: onSelectImage)
                            .buttonStyle(CoolDarkButtonStyle(isPrimary: true))
                    }
                }

                // Monitor outlines
                if selectedImage != nil {
                    MonitorPreviewView(
                        screens: manager.connectedScreens,
                        bounds: bounds,
                        previewScale: previewScale,
                        canvasWidth: canvasWidth,
                        canvasHeight: canvasHeight
                    )
                }
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.cdAccent, lineWidth: 2)
                    .opacity(isDropTargeted ? 1 : 0)
            )
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .focusable(selectedImage != nil)
            .focused($isCanvasFocused)
            .onTapGesture { isCanvasFocused = selectedImage != nil }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                guard let image = selectedImage else { return .ignored }
                let distance: CGFloat = press.modifiers.contains(.shift) ? 10 : 1
                let delta: CGSize
                switch press.key {
                case .leftArrow: delta = CGSize(width: -distance, height: 0)
                case .rightArrow: delta = CGSize(width: distance, height: 0)
                case .upArrow: delta = CGSize(width: 0, height: -distance)
                case .downArrow: delta = CGSize(width: 0, height: distance)
                default: return .ignored
                }
                nudgeImage(
                    byCanvasPoints: delta,
                    imageSize: image.pixelSize,
                    previewScale: previewScale
                )
                return .handled
            }
            .dropDestination(for: URL.self) { urls, _ in
                acceptDrop(urls)
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
        }
        .background(Color.cdCanvasBg)
    }

    /// Forwards the image files in a drop; refuses drops that carry none.
    private func acceptDrop(_ urls: [URL]) -> Bool {
        let images = ImageFileFilter.imageURLs(from: urls)
        guard !images.isEmpty else { return false }
        onDropImages(images)
        return true
    }

    /// Pushes the fitted scale to the parent binding; deferred because it runs during body evaluation.
    private func updatePreviewScale(_ scale: CGFloat) {
        DispatchQueue.main.async {
            if currentPreviewScale != scale {
                currentPreviewScale = scale
            }
        }
    }

    /// Scale that fits the bezel bounds into the available space with a 15% margin.
    private func calculatePreviewScale(geo: GeometryProxy) -> CGFloat {
        let scaleX = geo.size.width / max(manager.previewBounds.width, 1)
        let scaleY = geo.size.height / max(manager.previewBounds.height, 1)
        return min(scaleX, scaleY) * 0.85
    }

    /// Snaps a dragged offset to the canvas centre and edges within a 10 pt threshold.
    private func calculateSnapping(raw: CGSize, imgSize: NSSize, canvasSize: CGSize, previewScale: CGFloat, zoomScale: CGFloat) -> CGSize {
        var newX = raw.width
        var newY = raw.height
        let threshold: CGFloat = 10.0

        let w = imgSize.width * previewScale * zoomScale
        let h = imgSize.height * previewScale * zoomScale
        let cw = canvasSize.width * previewScale
        let ch = canvasSize.height * previewScale

        if abs(newX) < threshold { newX = 0 }
        if abs(newY) < threshold { newY = 0 }

        if abs(newX - (w - cw) / 2.0) < threshold { newX = (w - cw) / 2.0 }
        if abs(newX - -(w - cw) / 2.0) < threshold { newX = -(w - cw) / 2.0 }
        if abs(newY - (h - ch) / 2.0) < threshold { newY = (h - ch) / 2.0 }
        if abs(newY - -(h - ch) / 2.0) < threshold { newY = -(h - ch) / 2.0 }

        return constrainedOffset(raw: CGSize(width: newX, height: newY), imageWidth: w, imageHeight: h, canvasHeight: ch)
    }

    /// Moves the focused image by exact canvas points: one per arrow press, or ten
    /// while Shift is held. Stored offsets are preview points, hence the conversion.
    private func nudgeImage(byCanvasPoints delta: CGSize, imageSize: NSSize, previewScale: CGFloat) {
        let w = imageSize.width * previewScale * imageScale
        let h = imageSize.height * previewScale * imageScale
        let ch = manager.totalCanvas.height * previewScale
        let raw = CGSize(
            width: imageOffset.width + delta.width * previewScale,
            height: imageOffset.height + delta.height * previewScale
        )
        imageOffset = constrainedOffset(raw: raw, imageWidth: w, imageHeight: h, canvasHeight: ch)
        dragStartOffset = imageOffset
    }

    /// Wraps horizontal movement and clamps vertical movement to real overscan.
    private func constrainedOffset(raw: CGSize, imageWidth: CGFloat, imageHeight: CGFloat, canvasHeight: CGFloat) -> CGSize {
        func wrapped(_ value: CGFloat, period: CGFloat) -> CGFloat {
            guard period > 0 else { return 0 }
            return value - (value / period).rounded() * period
        }

        let verticalLimit = max(0, (imageHeight - canvasHeight) / 2.0)
        let clampedY = min(max(raw.height, -verticalLimit), verticalLimit)
        return CGSize(width: wrapped(raw.width, period: imageWidth), height: clampedY)
    }
}
