import PixelCompanionCore
import SwiftUI

/// Draws the companion's pixel sprite for `mood`, looping its animation frames.
struct CharacterView: View {
    let mood: CharacterMood
    var pixelSize: CGFloat = 2

    private static let frameDuration: TimeInterval = 0.6

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.frameDuration)) { context in
            let frames = CharacterSprite.frames(for: mood)
            let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.frameDuration)
            let palette = CharacterPalette(mood: mood)
            let scale = pixelSize
            Canvas { graphics, _ in
                guard !frames.isEmpty else { return }
                palette.draw(frames[tick % frames.count], pixelSize: scale, in: &graphics)
            }
        }
        .frame(width: CGFloat(CharacterSprite.width) * pixelSize, height: CGFloat(CharacterSprite.height) * pixelSize)
        .accessibilityElement()
        .accessibilityLabel("Companion: \(mood.title)")
    }
}

/// Colours per mood. Body colour carries the state; the face stays dark for contrast.
struct CharacterPalette {
    let body: Color
    let accent: Color

    init(mood: CharacterMood) {
        switch mood {
        case .idle:
            body = Color(red: 0.56, green: 0.86, blue: 0.72)
            accent = .white
        case .working:
            body = Color(red: 0.45, green: 0.72, blue: 1.0)
            accent = .yellow
        case .waitingForApproval:
            body = Color(red: 1.0, green: 0.78, blue: 0.35)
            accent = .white
        case .error:
            body = Color(red: 1.0, green: 0.45, blue: 0.42)
            accent = Color(red: 1.0, green: 0.85, blue: 0.3)
        case .offline:
            body = Color(red: 0.6, green: 0.6, blue: 0.64)
            accent = Color(red: 0.75, green: 0.8, blue: 0.95)
        case .thinking, .reviewing:
            body = Color(red: 0.65, green: 0.67, blue: 0.98)
            accent = .white
        case .coding:
            body = Color(red: 0.42, green: 0.82, blue: 0.95)
            accent = .yellow
        case .testing, .success:
            body = Color(red: 0.35, green: 0.84, blue: 0.58)
            accent = .yellow
        case .budgetWarning:
            body = Color(red: 0.99, green: 0.73, blue: 0.34)
            accent = .white
        case .infrastructureAlert, .securityAlert:
            body = Color(red: 0.96, green: 0.41, blue: 0.46)
            accent = .yellow
        }
    }

    func draw(_ sprite: CharacterSprite, pixelSize: CGFloat, in graphics: inout GraphicsContext) {
        for (row, pixels) in sprite.pixels.enumerated() {
            for (column, pixel) in pixels.enumerated() {
                guard let pixel else { continue }
                let rect = CGRect(
                    x: CGFloat(column) * pixelSize,
                    y: CGFloat(row) * pixelSize,
                    width: pixelSize,
                    height: pixelSize
                )
                graphics.fill(Path(rect), with: .color(color(for: pixel)))
            }
        }
    }

    func color(for pixel: CharacterSprite.Pixel) -> Color {
        switch pixel {
        case .body: return body
        case .highlight: return .white.opacity(0.85)
        case .eye, .mouth: return Color(red: 0.1, green: 0.1, blue: 0.12)
        case .accent: return accent
        }
    }
}
