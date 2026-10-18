import ScribeCore
import SwiftUI

/// DESIGN: A slim row of native controls above the transcript; colour comes from ScribeUI at the turn.
struct MeetingPlayerBar: View {
    let player: MeetingPlayback
    var body: some View {
        HStack(spacing: 8) {
            Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") { player.toggle() }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
            Text(MeetingTime.stamp(player.position)).monospacedDigit().font(.caption)
            Slider(value: Binding(get: { player.position }, set: { player.seek($0) }), in: 0...max(0.01, player.duration))
                .accessibilityLabel("Playback position")
            Text(MeetingTime.stamp(player.duration)).monospacedDigit().font(.caption).foregroundStyle(.secondary)
            Button(player.speed == 1 ? "1×" : player.speed == 1.5 ? "1.5×" : "2×") { player.cycleSpeed() }
                .buttonStyle(.borderless).accessibilityLabel("Playback speed")
        }
        if let error = player.error { Text(error).font(.caption).foregroundStyle(.secondary) }
    }
}
