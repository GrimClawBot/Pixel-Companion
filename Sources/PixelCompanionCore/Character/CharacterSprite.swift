import Foundation

/// Original pixel art for the companion: a small round blob whose face and accent change with
/// its mood. Drawn for this project; no third-party assets.
///
/// Legend: `.` empty, `B` body, `H` highlight, `E` eye, `M` mouth, `A` mood accent.
public struct CharacterSprite: Equatable, Sendable {
    public enum Pixel: Character, CaseIterable, Sendable {
        case body = "B"
        case highlight = "H"
        case eye = "E"
        case mouth = "M"
        case accent = "A"
    }

    public static let width = 12
    public static let height = 10

    /// Row-major; `nil` is transparent.
    public let pixels: [[Pixel?]]

    /// Parses `rows`; unknown characters are transparent.
    public init(rows: [String]) {
        pixels = rows.map { row in row.map { Pixel(rawValue: $0) } }
    }

    /// Animation frames for `mood`, played in order and looped.
    public static func frames(for mood: CharacterMood) -> [CharacterSprite] {
        let fallback: CharacterMood
        switch mood {
        case .thinking, .coding, .testing, .reviewing: fallback = .working
        case .success: fallback = .idle
        case .budgetWarning: fallback = .waitingForApproval
        case .infrastructureAlert, .securityAlert: fallback = .error
        default: fallback = mood
        }
        return (rows[fallback] ?? []).map(CharacterSprite.init(rows:))
    }

    private static let feetApart = "..BB....BB.."
    private static let feetTogether = "...BB..BB..."

    private static let rows: [CharacterMood: [[String]]] = [
        .idle: [
            [
                "....BBBB....", "..BBBBBBBB..", ".BBHBBBBBBB.", ".BBBBBBBBBB.", "BBBEBBBBEBBB",
                "BBBEBBBBEBBB", "BBBMBBBBMBBB", ".BBBMMMMBBB.", "..BBBBBBBB..", feetApart
            ],
            [
                "....BBBB....", "..BBBBBBBB..", ".BBHBBBBBBB.", ".BBBBBBBBBB.", "BBBBBBBBBBBB",
                "BBEEBBBBEEBB", "BBBMBBBBMBBB", ".BBBMMMMBBB.", "..BBBBBBBB..", feetApart
            ]
        ],
        .working: [
            [
                "....BBBB..A.", "..BBBBBBBB..", ".BBHBBBBBBB.", ".BBBBBBBBBB.", "BBBBBBBBBBBB",
                "BBBEEBBEEBBB", "BBBBBBBBBBBB", ".BBBMMMMBBB.", "..BBBBBBBB..", feetApart
            ],
            [
                "....BBBB....", "..BBBBBBBB.A", ".BBHBBBBBBB.", ".BBBBBBBBBB.", "BBBBBBBBBBBB",
                "BBBEEBBEEBBB", "BBBBBBBBBBBB", ".BBBMMMMBBB.", "..BBBBBBBB..", feetTogether
            ]
        ],
        .waitingForApproval: [
            [
                "....BBBB..A.", "..BBBBBBBBA.", ".BBHBBBBBBB.", ".BBBBBBBBBBA", "BBBEBBBBEBBB",
                "BBBEBBBBEBBB", "BBBBBBBBBBBB", ".BBBBMMBBBB.", "..BBBBBBBB..", feetApart
            ],
            [
                "....BBBB....", "..BBBBBBBB..", ".BBHBBBBBBB.", ".BBBBBBBBBB.", "BBBEBBBBEBBB",
                "BBBEBBBBEBBB", "BBBBBBBBBBBB", ".BBBBMMBBBB.", "..BBBBBBBB..", feetApart
            ]
        ],
        .error: [
            [
                "....BBBB....", "..BBBBBBBB..", ".BBHBBBBBBB.", ".BEBEBBEBEB.", "BBBEBBBBEBBB",
                "BBEBEBBEBEBB", "BBBBBBBBBBBB", ".BBBMMMMBBB.", "..BMBBBBMB..", feetApart
            ],
            [
                "A...BBBB...A", "..BBBBBBBB..", ".BBHBBBBBBB.", ".BEBEBBEBEB.", "BBBEBBBBEBBB",
                "BBEBEBBEBEBB", "BBBBBBBBBBBB", ".BBBMMMMBBB.", "..BMBBBBMB..", feetApart
            ]
        ],
        .offline: [
            [
                "....BBBB...A", "..BBBBBBBB..", ".BBBBBBBBBB.", ".BBBBBBBBBB.", "BBBBBBBBBBBB",
                "BBEEBBBBEEBB", "BBBBBBBBBBBB", ".BBBBMMBBBB.", "..BBBBBBBB..", feetTogether
            ],
            [
                "....BBBB....", "..BBBBBBBBA.", ".BBBBBBBBBB.", ".BBBBBBBBBB.", "BBBBBBBBBBBB",
                "BBEEBBBBEEBB", "BBBBBBBBBBBB", ".BBBBMMBBBB.", "..BBBBBBBB..", feetTogether
            ]
        ]
    ]
}
