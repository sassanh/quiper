import UIKit
import Foundation

/// UIKit implementation of `FaviconImageProcessing` used by the iOS app.
enum UIKitFaviconImageProcessor: FaviconImageProcessing {
    /// Checks if a base64 PNG string is high resolution (>= 96x96 pixels)
    @MainActor
    static func isHighRes(base64: String) -> Bool {
        guard let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else {
            return false
        }
        let pixelWidth = image.size.width * image.scale
        return pixelWidth >= 96
    }

    /// Converts an image to its PNG representation and returns its Base64 string.
    /// Caps large images at a maximum bounding box of 128x128 for storage efficiency.
    @MainActor
    static func encodePNG(data: Data) -> String? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale

        let maxDimension: CGFloat = 128.0
        let targetSize: CGSize
        if pixelWidth > maxDimension || pixelHeight > maxDimension {
            let ratio = min(maxDimension / pixelWidth, maxDimension / pixelHeight)
            targetSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)
        } else {
            targetSize = CGSize(width: pixelWidth, height: pixelHeight)
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard hasVisiblePixels(resized),
              let pngData = resized.pngData() else {
            return nil
        }

        return pngData.base64EncodedString()
    }

    @MainActor
    private static func hasVisiblePixels(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return true }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var index = 3
        while index < pixels.count {
            if Double(pixels[index]) / 255.0 > 0.01 {
                return true
            }
            index += 4
        }

        return false
    }
}
