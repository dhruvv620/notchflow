// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620
import AppKit
import CoreAudio
import Darwin
import Foundation

/// Which processes are using the microphone and speakers right now (CoreAudio
/// process objects, macOS 14.2+). Needs no permission and reads no audio.
enum CallAudioMonitor {
    static func processes() -> [CallAudioPolicy.Process] {
        guard #available(macOS 14.2, *) else { return [] }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let input = uint32(id, kAudioProcessPropertyIsRunningInput) == 1
            guard input else { return nil }
            let output = uint32(id, kAudioProcessPropertyIsRunningOutput) == 1
            let pid = Int32(bitPattern: uint32(id, kAudioProcessPropertyPID) ?? 0)
            return CallAudioPolicy.Process(pid: pid, bundleID: string(id, kAudioProcessPropertyBundleID) ?? "",
                                           name: processName(pid), input: input, output: output)
        }
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func processName(_ pid: Int32) -> String {
        guard pid > 0 else { return "" }
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName, !name.isEmpty { return name }
        var buffer = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
    }
}

/// Mutes the Mac's microphone (the default input device) for any call app.
/// Uses the device's mute switch when it has one, otherwise sets its input
/// volume to zero and puts it back afterwards.
@MainActor
final class SystemMicrophone: ObservableObject {
    static let shared = SystemMicrophone()
    @Published private(set) var isMuted = false
    /// The input volume before NotchFlow muted it (volume fallback only).
    private var savedVolume: Float32?
    private var mutedByUs = false

    private init() { isMuted = readMuted() }

    func refresh() { isMuted = readMuted() }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard let device = Self.defaultInput() else { return false }
        var ok = false
        if Self.settable(device, kAudioDevicePropertyMute) {
            var value: UInt32 = muted ? 1 : 0
            ok = Self.set(device, kAudioDevicePropertyMute, &value)
        }
        if !ok, Self.settable(device, kAudioDevicePropertyVolumeScalar) {
            if muted {
                if savedVolume == nil { savedVolume = Self.volume(device) ?? 1 }
                var zero: Float32 = 0
                ok = Self.set(device, kAudioDevicePropertyVolumeScalar, &zero)
            } else {
                var restored = savedVolume ?? 1
                ok = Self.set(device, kAudioDevicePropertyVolumeScalar, &restored)
                if ok { savedVolume = nil }
            }
        }
        if ok { mutedByUs = muted }
        isMuted = readMuted()
        return ok
    }

    /// Puts the microphone back once no call needs it muted.
    func releaseIfMutedByUs() {
        guard mutedByUs else { return }
        setMuted(false)
    }

    private func readMuted() -> Bool {
        guard let device = Self.defaultInput() else { return false }
        if let mute: UInt32 = Self.get(device, kAudioDevicePropertyMute), mute == 1 { return true }
        return savedVolume != nil && (Self.volume(device) ?? 1) < 0.01
    }

    private static func defaultInput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func inputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func settable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = inputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func get<T>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> T? where T: BinaryInteger {
        var address = inputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func volume(_ device: AudioDeviceID) -> Float32? {
        var address = inputAddress(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func set<T>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = inputAddress(selector)
        let size = UInt32(MemoryLayout<T>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }
}
