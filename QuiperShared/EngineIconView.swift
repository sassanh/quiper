import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared SwiftUI rendering of an engine icon: the decoded image from the engine's
/// base64 icon, or the globe placeholder when there is none.
struct EngineIconView: View {
    let service: Service?
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let icon = Self.makeImage(from: service?.iconBase64) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.21)))
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }

    private static func makeImage(from base64: String?) -> Image? {
        guard let base64, let data = Data(base64Encoded: base64) else { return nil }
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}
