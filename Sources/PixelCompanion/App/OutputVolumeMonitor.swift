import Combine
import CoreAudio
import Foundation

/// Public CoreAudio GET-only queries. Missing master output controls (common
/// with external/digital devices) are unavailable, never estimated.
enum CoreAudioOutputVolumeReader {
    static func read() -> OutputVolumeSample? {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress,
            0, nil, &deviceSize, &deviceID
        ) == noErr,
              deviceSize == MemoryLayout<AudioObjectID>.size,
              deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &volumeAddress) else { return nil }
        var scalar: Float32 = 0
        var scalarSize = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &volumeAddress, 0, nil, &scalarSize, &scalar
        ) == noErr,
              scalarSize == MemoryLayout<Float32>.size else { return nil }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isMuted: Bool?
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            var muteFlag: UInt32 = 0
            var muteSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(
                deviceID, &muteAddress, 0, nil, &muteSize, &muteFlag
            ) == noErr, muteSize == MemoryLayout<UInt32>.size {
                isMuted = muteFlag != 0
            }
        }
        return OutputVolumeSample(scalar: Double(scalar), isMuted: isMuted)
    }
}

/// A conservative, local-only status refresh; never registers an audio tap,
/// requests microphone access or calls any setter.
@MainActor
final class OutputVolumeMonitor: ObservableObject {
    @Published private(set) var snapshot = OutputVolumeSnapshot.unavailable
    private let readOutput: () -> OutputVolumeSample?
    private var ticker: Timer?
    private(set) var enabled = false

    static let refreshInterval: TimeInterval = 10

    init(readOutput: @escaping () -> OutputVolumeSample? = CoreAudioOutputVolumeReader.read) {
        self.readOutput = readOutput
    }

    func configure(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        if newValue {
            refresh()
            let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else {
            ticker?.invalidate()
            ticker = nil
            snapshot = .unavailable
        }
    }

    func refresh() {
        guard enabled else { return }
        let next = OutputVolumeSnapshot.validated(readOutput())
        if snapshot != next { snapshot = next }
    }
}
