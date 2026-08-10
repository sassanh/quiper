import SwiftUI

extension View {
    /// Applies the native Liquid Glass appearance required by Quiper's iOS 26 floor.
    func glassIsland(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(glass(in: shape, tint: tint, interactive: interactive))
    }

    /// Coordinates nearby glass elements so they render and morph as one surface.
    func glassContainer() -> some View {
        GlassEffectContainer { self }
    }

    private func glass<S: Shape>(in shape: S, tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}
