import AudioToolbox
import CoreAudio
import Foundation

/// Follows the Mac's output volume and mute state, for the menu bar icon.
///
/// CoreAudio tells us when the volume, mute or output device changes, so the
/// icon updates as you press the volume keys. A slow two-second check runs as
/// well, because some devices (Bluetooth, USB) don't report every change.
@MainActor
final class VolumeMonitor: ObservableObject {
    /// 0 (silent) ... 1 (full).
    @Published private(set) var level: Double = 0.5
    @Published private(set) var muted = false

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var timer: Timer?

    init() {
        var defaultDevice = Self.makeAddress(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultDevice() }
        }
        attachToDefaultDevice()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// The same symbols the system Sound item uses: no waves at zero, then one to three.
    var symbolName: String {
        if muted { return "speaker.slash.fill" }
        switch level {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private func attachToDefaultDevice() {
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        }
        deviceListeners = []
        deviceID = Self.defaultOutputDevice()

        if deviceID != AudioObjectID(kAudioObjectUnknown) {
            let watched: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
                (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
                (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
                (kAudioDevicePropertyVolumeScalar, 1),
                (kAudioDevicePropertyVolumeScalar, 2),
                (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
            ]
            for (selector, element) in watched {
                var address = Self.makeAddress(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
                // Devices only support some of these; the rest simply fail to register.
                if AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block) == noErr {
                    deviceListeners.append((address, block))
                }
            }
        }
        refresh()
    }

    private func refresh() {
        if Self.defaultOutputDevice() != deviceID {
            attachToDefaultDevice()
            return
        }
        // A device with no volume control (e.g. some HDMI outputs) keeps the last level.
        if let newLevel = Self.volume(of: deviceID), abs(newLevel - level) > 0.001 {
            level = newLevel
        }
        let newMuted = Self.isMuted(deviceID)
        if newMuted != muted {
            muted = newMuted
        }
    }

    // MARK: CoreAudio reads

    private static func makeAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var address = makeAddress(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr ? id : AudioObjectID(kAudioObjectUnknown)
    }

    private static func readFloat(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Double? {
        var address = makeAddress(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    /// The overall volume if the device reports one, otherwise the average of
    /// the left and right channels.
    private static func volume(of id: AudioObjectID) -> Double? {
        guard id != AudioObjectID(kAudioObjectUnknown) else { return nil }
        if let main = readFloat(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, element: kAudioObjectPropertyElementMain) {
            return main
        }
        if let main = readFloat(id, kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return main
        }
        let channels = [UInt32(1), UInt32(2)].compactMap { readFloat(id, kAudioDevicePropertyVolumeScalar, element: $0) }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Double(channels.count)
    }

    private static func isMuted(_ id: AudioObjectID) -> Bool {
        guard id != AudioObjectID(kAudioObjectUnknown) else { return false }
        var address = makeAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }
}
