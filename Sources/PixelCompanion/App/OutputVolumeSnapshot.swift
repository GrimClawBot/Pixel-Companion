import Foundation

/// Only the default output's reported scalar and mute flag are kept in RAM.
/// No audio, input-device access, device name or hardware identifier is retained.
struct OutputVolumeSample: Equatable, Sendable {
    let scalar: Double
    let isMuted: Bool?
}

struct OutputVolumeSnapshot: Equatable, Sendable {
    let percentage: Int?
    let isMuted: Bool?

    static let unavailable = OutputVolumeSnapshot(percentage: nil, isMuted: nil)

    static func validated(_ sample: OutputVolumeSample?) -> OutputVolumeSnapshot {
        guard let sample,
              sample.scalar.isFinite,
              (0.0...1.0).contains(sample.scalar) else { return .unavailable }
        return OutputVolumeSnapshot(
            percentage: Int((sample.scalar * 100).rounded()),
            isMuted: sample.isMuted
        )
    }
}
