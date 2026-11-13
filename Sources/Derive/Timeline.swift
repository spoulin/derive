import SwiftUI

/// Where the track playing is: a thin bar with the elapsed time on the left and the time left on
/// the right. Click or drag the bar to move in the track.
struct TrackTimeline: View {
    @ObservedObject private var clock = Player.shared.clock
    let compact: Bool
    /// While dragging, the position under the pointer, shown before the seek happens.
    @State private var dragging: Double?
    @State private var hovering = false

    var body: some View {
        let duration = clock.duration
        let shown = dragging ?? clock.elapsed
        let fraction = duration > 0 ? min(max(shown / duration, 0), 1) : 0
        VStack(spacing: compact ? 2 : 4) {
            GeometryReader { geo in
                let height: CGFloat = hovering || dragging != nil ? 6 : 4
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.18))
                    Capsule().fill(Color.primary.opacity(0.85))
                        .frame(width: max(height, geo.size.width * fraction))
                }
                .frame(height: height)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            dragging = min(max(value.location.x / geo.size.width, 0), 1) * duration
                        }
                        .onEnded { _ in
                            if let target = dragging { Player.shared.seek(to: target) }
                            dragging = nil
                        }
                )
                .animation(.easeOut(duration: 0.15), value: height)
            }
            .frame(height: 12)
            .onHover { hovering = $0 }

            HStack {
                Text(Self.format(shown))
                Spacer()
                Text("-" + Self.format(max(duration - shown, 0)))
            }
            .font((compact ? Font.caption2 : Font.caption).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        // Keeps its room when nothing plays, so the controls don't move.
        .opacity(duration > 0 ? 1 : 0)
        .disabled(duration <= 0)
        .help("Click or drag to move in the track")
    }

    /// 83 -> "1:23", 3725 -> "1:02:05".
    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
