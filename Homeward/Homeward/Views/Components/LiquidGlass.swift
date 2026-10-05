import SwiftUI

// Apple's Liquid Glass (iOS 26) for the navigation and control layer only: tab bar, toolbars, floating actions,
// controls and overlays. Content (cards, receipts, lists) never gets glass; see `contentSurface()`.
// On iOS 17–25 these helpers fall back to a frosted material so the app keeps the same structure.

extension View {
    /// Liquid Glass behind this control. `clear` is for small controls over media (like the map);
    /// `tint` is for the one primary action on screen; `interactive` makes the glass react to touch.
    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, clear: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(LiquidGlassStyle.make(clear: clear, tint: tint, interactive: interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.85)) }
                    shape.stroke(.white.opacity(0.22), lineWidth: 1)
                }
            }
        }
    }

    /// Identifies a glass shape so it can morph into another during animated changes.
    @ViewBuilder
    func liquidGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// System glass button styles: `.glassProminent` for the primary action, `.glass` otherwise.
    @ViewBuilder
    func liquidGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }

    /// A solid surface for content: cards, receipts, list sections. Never glass.
    func contentSurface(cornerRadius: CGFloat = 24) -> some View {
        modifier(ContentSurface(cornerRadius: cornerRadius))
    }
}

@available(iOS 26.0, *)
private enum LiquidGlassStyle {
    static func make(clear: Bool, tint: Color?, interactive: Bool) -> Glass {
        var glass: Glass = clear ? .clear : .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Groups nearby glass so it renders together and can blend and morph (GlassEffectContainer on iOS 26).
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

struct ContentSurface: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 12, y: 6)
    }
}
