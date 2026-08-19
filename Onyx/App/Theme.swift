import SwiftUI

/// Paleta minimalista: base negra con acentos suaves y desaturados.
enum Theme {
    static let bg            = Color(hex: 0x0A0A0C)   // fondo
    static let surface       = Color(hex: 0x141418)   // tarjetas
    static let surfaceHigh   = Color(hex: 0x1C1C22)   // elementos elevados
    static let stroke        = Color(hex: 0x26262D)   // bordes sutiles

    static let text          = Color(hex: 0xF2F2F4)
    static let textMuted     = Color(hex: 0x8A8A93)
    static let textFaint     = Color(hex: 0x5A5A63)

    static let accent        = Color(hex: 0xC9B79C)   // arena cálida
    static let accentAlt     = Color(hex: 0x8FA1B3)   // niebla azul
    static let star          = Color(hex: 0xE0C378)   // dorado suave
    static let danger        = Color(hex: 0xC98686)   // rojo apagado

    static let corner: CGFloat = 14
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Tarjeta base reutilizable.
struct CardBackground: ViewModifier {
    var elevated: Bool = false
    func body(content: Content) -> some View {
        content
            .background(elevated ? Theme.surfaceHigh : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func card(elevated: Bool = false) -> some View {
        modifier(CardBackground(elevated: elevated))
    }
}

/// Barra de progreso fina y discreta.
struct ProgressBar: View {
    let value: Double          // 0...1
    var height: CGFloat = 3
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.stroke)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
