import ScribeCore
import ScribeUI
import SwiftUI

struct MeetingRecordingView: View {
    let recorder: MeetingRecorder
    @State private var microphone: MeetingSourceHealth = .level(0)
    @State private var callAudio: MeetingSourceHealth = .none

    var body: some View {
        MeetingRecordingContent(elapsed: recorder.elapsed, paused: recorder.paused,
            microphone: microphone, callAudio: callAudio, changingPause: recorder.changingPause,
            pause: { Task { await recorder.togglePause() } }, stop: { Task { await recorder.stop() } })
            .task {
                while !Task.isCancelled, let session = recorder.session {
                    microphone = await session.sourceHealth(MeetingAudioSegment.microphone)
                    callAudio = await session.sourceHealth(MeetingAudioSegment.system)
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
    }
}

/// Values, rather than the recorder, keep ten-Hz metering confined to the recording column.
struct MeetingRecordingContent: View {
    var elapsed: Double
    var paused: Bool
    var microphone: MeetingSourceHealth
    var callAudio: MeetingSourceHealth
    var changingPause = false
    var pause: () -> Void
    var stop: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(MeetingTime.stamp(elapsed)).font(.system(size: 44, weight: .semibold)).monospacedDigit()
                Text(paused ? "Paused" : "Recording").font(.system(size: 13))
                    .foregroundStyle(paused ? Color.secondary : Brand.coral)
            }
            VStack(spacing: 16) {
                MeetingSourceRow(title: "Microphone", symbol: "mic", health: paused ? .paused : microphone)
                MeetingSourceRow(title: "Call audio", symbol: "speaker.wave.2", health: paused ? .paused : callAudio)
            }
            HStack(spacing: 12) {
                Button(paused ? "Resume" : "Pause", action: pause).buttonStyle(.bordered).disabled(changingPause)
                Button("Stop", action: stop).buttonStyle(.borderedProminent).tint(Brand.coral)
            }
        }.frame(width: 360).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MeetingSourceRow: View {
    let title: String
    let symbol: String
    let health: MeetingSourceHealth
    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            switch health {
            case .level(let level):
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<3) { index in
                        Rectangle().fill(Brand.sky)
                            .frame(width: 3, height: 2 + 8 * min(1, max(0, level * Double(12 - index * 3))))
                    }
                }.frame(height: 10).accessibilityLabel("Audio level").accessibilityValue(level.formatted(.percent.precision(.fractionLength(0))))
            case .warning(let reason):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.amber)
                Text(reason).foregroundStyle(.secondary)
            case .none: Text("None — in-person").foregroundStyle(.secondary)
            case .paused:
                // DESIGN: Paused sources use native secondary text in place of a live level.
                Text("Paused").foregroundStyle(.secondary)
            }
        }.font(.system(size: 13))
    }
}

struct MeetingProcessingView: View {
    let progress: MeetingProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(progress.steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    glyph(progress[step]).frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.rawValue)
                        if case .failed(let error) = progress[step] { Text(error).foregroundStyle(.secondary) }
                    }
                }
            }
        }.frame(width: 360, alignment: .leading)
    }
    @ViewBuilder private func glyph(_ status: MeetingProgress.Status) -> some View {
        switch status {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .active: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.sky)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.amber)
        }
    }
}
