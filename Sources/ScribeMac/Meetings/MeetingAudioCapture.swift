import AppKit
import AVFoundation
import CoreAudio
import ScribeCore
import Synchronization


enum MeetingCaptureError: LocalizedError {
    case systemAudio(OSStatus), noAudio, write(String), microphoneStalled
    var errorDescription: String? {
        switch self {
        case .systemAudio(let code):
            "System audio recording couldn't start (\(code)). Allow NanthAi Scribe in System Settings › Privacy & Security › Screen & System Audio Recording."
        case .noAudio: "No audio was received from the microphone or other apps."
        case .write(let message): "The recording couldn't be saved: \(message)"
        case .microphoneStalled: "The microphone stopped delivering audio."
        }
    }
}

/// One capture stream (microphone or system). Each `start` opens a new file; interruptions
/// (device change, sleep) are reported so the session can restart into a new segment.
protocol MeetingAudioSource: AnyObject, Sendable {
    func start(url: URL) async throws
    func stop() async throws
    var frames: Int64 { get async }
    var level: Double { get async }
    var hasSignal: Bool { get async }
    var firstHostTime: Double? { get async }
    func observeInterruptions(_ handler: @escaping @Sendable () -> Void) async
    func release() async
}

extension MeetingAudioSource {
    var level: Double { get async { 0 } }
    var hasSignal: Bool { get async { await level > 0.0001 } }
}

/// Independent engine: a meeting never acquires Dictation's microphone or HUD.
@MainActor
final class MeetingMicrophone: MeetingAudioSource {
    private let engine = AVAudioEngine()
    private var installed = false
    private var observer: NSObjectProtocol?
    private(set) var writer: MeetingAudioWriter?
    var frames: Int64 { writer?.frames ?? 0 }
    var level: Double { writer?.level ?? 0 }
    var hasSignal: Bool { writer?.hasSignal ?? false }
    var firstHostTime: Double? { writer?.firstHostTime }
    func start(url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw ScribeError.microphoneUnavailable }
        let writer = try MeetingAudioWriter(url: url, format: format)
        self.writer = writer
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tap(writer))
        installed = true
        do { try engine.start() } catch { try? stop(); throw error }
    }
    private nonisolated static func tap(_ writer: MeetingAudioWriter) -> AVAudioNodeTapBlock {
        { buffer, time in writer.append(buffer.audioBufferList, hostTime: time.hostTime) }
    }
    func stop() throws {
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        engine.stop()
        try writer?.finish()
    }
    /// The engine stops itself when the input device or its format changes (AirPods connecting).
    func observeInterruptions(_ handler: @escaping @Sendable () -> Void) {
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: .main) { _ in handler() }
    }
    func release() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}

actor MeetingSystemAudio: MeetingAudioSource {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var listener: AudioObjectPropertyListenerBlock?
    private(set) var writer: MeetingAudioWriter?
    var frames: Int64 { writer?.frames ?? 0 }
    var level: Double { writer?.level ?? 0 }
    var hasSignal: Bool { writer?.hasSignal ?? false }
    var firstHostTime: Double? { writer?.firstHostTime }

    func start(url: URL) throws {
        do {
            var pid = getpid()
            var process: AudioObjectID = 0
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process))
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [process])
            description.name = "NanthAi Scribe meeting"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tap))
            address.mSelector = kAudioTapPropertyFormat
            var stream = AudioStreamBasicDescription()
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &stream))
            guard let format = AVAudioFormat(streamDescription: &stream) else { throw ScribeError.noAudioFormat }
            let writer = try MeetingAudioWriter(url: url, format: format)
            self.writer = writer
            // Give the aggregate a hardware clock. A tap-only aggregate can stall IO registration.
            var output: AudioObjectID = 0
            size = UInt32(MemoryLayout<AudioObjectID>.size)
            address.mSelector = kAudioHardwarePropertyDefaultOutputDevice
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &output))
            var rawUID: Unmanaged<CFString>?
            size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            address.mSelector = kAudioDevicePropertyDeviceUID
            try check(AudioObjectGetPropertyData(output, &address, 0, nil, &size, &rawUID))
            guard let outputUID = rawUID?.takeRetainedValue() else { throw ScribeError.noAudioFormat }
            let specification: [String: Any] = [
                kAudioAggregateDeviceNameKey: "NanthAi Scribe meeting",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                   kAudioSubTapDriftCompensationKey: true]],
            ]
            try check(AudioHardwareCreateAggregateDevice(specification as CFDictionary, &aggregate))
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil, Self.ioProc(writer)))
            try check(AudioDeviceStart(aggregate, ioProc))
        } catch { try? stop(); throw error }
    }
    private nonisolated static func ioProc(_ writer: MeetingAudioWriter) -> AudioDeviceIOBlock {
        { _, input, time, _, _ in writer.append(input, hostTime: time.pointee.mHostTime, tapOnly: true) }
    }

    func stop() throws {
        if let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
            self.ioProc = nil
        }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        try writer?.finish()
    }
    /// The aggregate is clocked by the default output device; when that changes, the tap must be rebuilt on the new one.
    func observeInterruptions(_ handler: @escaping @Sendable () -> Void) {
        var address = Self.defaultOutputAddress
        let listener: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
            self.listener = listener
        }
    }
    func release() {
        guard let listener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = nil
    }
    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        .init(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
              mElement: kAudioObjectPropertyElementMain)
    }
    private func check(_ status: OSStatus) throws {
        if status != noErr { throw MeetingCaptureError.systemAudio(status) }
    }
}
