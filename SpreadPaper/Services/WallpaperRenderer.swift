import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Placement of one source image on one display. Every field is `Sendable`, so a
/// spec built on the main actor can be handed to a detached rendering task
/// without moving screen objects across isolation boundaries.
nonisolated struct RenderSpec: Sendable {
    /// Display frame in the spaced (bezel-compensated) layout, in points.
    var screenFrame: CGRect
    /// Union of all display frames, in points.
    var totalCanvas: CGRect
    /// Editor drag offset, in preview points.
    var offset: CGSize
    var imageScale: CGFloat
    var previewScale: CGFloat
    var isFlipped: Bool
    var deviceScale: CGFloat
    var colorSpace: CGColorSpace?

    /// Output size in pixels.
    var pixelSize: (width: Int, height: Int) {
        (Int(screenFrame.width * deviceScale), Int(screenFrame.height * deviceScale))
    }
}

/// Pure rendering and encoding. Safe to call off the main actor.
enum WallpaperRenderer {
    /// Draws the part of `source` that falls on the display described by `spec`.
    nonisolated static func render(_ source: CGImage, spec: RenderSpec) throws -> CGImage {
        let (widthPx, heightPx) = spec.pixelSize
        guard widthPx > 0, heightPx > 0 else { throw WallpaperError.contextCreationFailed }

        // Use the screen's native color space for better wide-gamut display support.
        let colorSpace = spec.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: widthPx,
            height: heightPx,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw WallpaperError.contextCreationFailed
        }

        let deviceScale = spec.deviceScale
        let imageWidth = CGFloat(source.width)
        let imageHeight = CGFloat(source.height)

        let realOffsetXPx = (spec.offset.width / spec.previewScale) * deviceScale
        let realOffsetYPx = (spec.offset.height / spec.previewScale) * deviceScale
        let drawnWidthPx = imageWidth * spec.imageScale * deviceScale
        let drawnHeightPx = imageHeight * spec.imageScale * deviceScale
        let canvasWidthPx = spec.totalCanvas.width * deviceScale
        let canvasHeightPx = spec.totalCanvas.height * deviceScale
        let centeringXPx = (canvasWidthPx - drawnWidthPx) / 2.0
        let centeringYPx = (canvasHeightPx - drawnHeightPx) / 2.0
        let relativeScreenX = spec.screenFrame.origin.x - spec.totalCanvas.origin.x
        let relativeScreenY = spec.screenFrame.origin.y - spec.totalCanvas.origin.y

        let drawX = centeringXPx + realOffsetXPx - (relativeScreenX * deviceScale)
        let drawY = centeringYPx - realOffsetYPx - (relativeScreenY * deviceScale)
        let drawRect = CGRect(x: drawX, y: drawY, width: drawnWidthPx, height: drawnHeightPx)

        context.interpolationQuality = .high

        // Repeat the image beyond every edge. Dragging a panorama out on one side
        // therefore brings it back in on the opposite side instead of exposing black.
        let xRange = tileRange(origin: drawRect.minX, length: drawRect.width, viewportLength: CGFloat(widthPx))
        let yRange = tileRange(origin: drawRect.minY, length: drawRect.height, viewportLength: CGFloat(heightPx))
        for y in yRange {
            for x in xRange {
                let tile = drawRect.offsetBy(dx: CGFloat(x) * drawRect.width, dy: CGFloat(y) * drawRect.height)
                if spec.isFlipped {
                    context.saveGState()
                    context.translateBy(x: tile.midX, y: tile.midY)
                    context.scaleBy(x: -1, y: 1)
                    context.translateBy(x: -tile.midX, y: -tile.midY)
                }
                context.draw(source, in: tile)
                if spec.isFlipped {
                    context.restoreGState()
                }
            }
        }

        guard let output = context.makeImage() else {
            throw WallpaperError.renderingFailed
        }
        return output
    }

    /// Tile indices whose translated image rectangles can intersect one viewport axis.
    nonisolated private static func tileRange(origin: CGFloat, length: CGFloat, viewportLength: CGFloat) -> ClosedRange<Int> {
        guard length > 0 else { return 0...0 }
        let first = Int(floor(-origin / length))
        let last = Int(ceil((viewportLength - origin) / length))
        return first...max(first, last)
    }

    /// Encodes `image` as PNG without touching AppKit.
    nonisolated static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw WallpaperError.pngEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw WallpaperError.pngEncodingFailed
        }
        return data as Data
    }
}
