import SwiftUI

/// A short message at the bottom of the player that says what an action just did. It fades in,
/// stays a few seconds, and fades out; a new one replaces the one showing.
@MainActor
final class Toast: ObservableObject {
    static let shared = Toast()

    struct Message: Equatable {
        let id = UUID()
        let symbol: String
        let text: String
    }

    @Published private(set) var message: Message?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, symbol: String) {
        let message = Message(symbol: symbol, text: text)
        withAnimation(.easeOut(duration: 0.2)) { self.message = message }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, self.message?.id == message.id else { return }
            withAnimation(.easeIn(duration: 0.4)) { self.message = nil }
        }
    }
}

/// Where the toast shows: laid over the bottom of the player.
struct ToastView: View {
    @ObservedObject private var toast = Toast.shared
    let compact: Bool

    var body: some View {
        ZStack {
            if let message = toast.message {
                HStack(spacing: 8) {
                    Image(systemName: message.symbol)
                    Text(message.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(compact ? .caption : .callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                .padding(.horizontal, 12)
                .id(message.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .allowsHitTesting(false)
    }
}
