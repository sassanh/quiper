import AppKit
import Foundation

/// AppKit implementation of `FaviconImageProcessing` used by the macOS app.
enum AppKitFaviconImageProcessor: FaviconImageProcessing {
    /// Checks if a base64 PNG string is high resolution (>= 96x96 pixels)
    @MainActor
    static func isHighRes(base64: String) -> Bool {
        guard let decodedData = Data(base64Encoded: base64),
              let image = NSImage(data: decodedData) else {
            return false
        }
        var sourceWidth: CGFloat = image.size.width
        for rep in image.representations {
            let w = CGFloat(rep.pixelsWide)
            if w > sourceWidth {
                sourceWidth = w
            }
        }
        return sourceWidth >= 96
    }

    /// Converts an image to its PNG representation and returns its Base64 string.
    /// Extracts the highest-resolution representation from multi-resolution files (like .ico)
    /// and caps large images at a maximum bounding box of 128x128 for storage efficiency.
    @MainActor
    static func encodePNG(data: Data) -> String? {
        guard let image = NSImage(data: data) else {
            return nil
        }

        // Find the maximum pixel dimensions among all representations
        var sourceWidth: CGFloat = image.size.width
        var sourceHeight: CGFloat = image.size.height

        for rep in image.representations {
            let w = CGFloat(rep.pixelsWide)
            let h = CGFloat(rep.pixelsHigh)
            if w > sourceWidth {
                sourceWidth = w
            }
            if h > sourceHeight {
                sourceHeight = h
            }
        }

        let maxDimension: CGFloat = 128.0
        let targetSize: NSSize
        if sourceWidth > maxDimension || sourceHeight > maxDimension {
            let ratio = min(maxDimension / sourceWidth, maxDimension / sourceHeight)
            targetSize = NSSize(width: sourceWidth * ratio, height: sourceHeight * ratio)
        } else {
            targetSize = NSSize(width: sourceWidth, height: sourceHeight)
        }

        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        // Passing .zero as 'fromRect' prompts AppKit to automatically select and draw the
        // best-fitting (highest-resolution) representation for the target destination rect.
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        resizedImage.unlockFocus()

        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              hasVisiblePixels(bitmapRep),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }

        return pngData.base64EncodedString()
    }

    @MainActor
    private static func hasVisiblePixels(_ bitmapRep: NSBitmapImageRep) -> Bool {
        guard bitmapRep.hasAlpha else { return true }

        for y in 0..<bitmapRep.pixelsHigh {
            for x in 0..<bitmapRep.pixelsWide {
                if bitmapRep.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.01 {
                    return true
                }
            }
        }

        return false
    }
}
