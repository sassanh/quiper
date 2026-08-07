import SwiftUI

extension View {
    /// Applies the native Liquid Glass appearance on iOS 26+, falling back to an
    /// ultra-thin material surface on earlier versions.
    @ViewBuilder
    func glassIsland(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(glass(in: shape, tint: tint, interactive: interactive))
        } else {
            if let tint {
                background(shape.fill(tint))
            } else {
                background(shape.fill(.ultraThinMaterial))
            }
        }
    }

    /// Coordinates nearby glass elements so they render and morph as one surface.
    @ViewBuilder
    func glassContainer() -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer { self }
        } else {
            self
        }
    }

    @available(iOS 26.0, *)
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
