import SwiftUI

/// The WisprOwn bar — a small always-on-top pill at the bottom of the
/// screen. Idle: a slim resting bar. Recording: a live waveform driven by
/// real mic levels. Transcribing: a pulsing-dots loader.
struct FlowBarView: View {
    @ObservedObject var app: AppState

    private enum Mode: Equatable { case idle, recording, transcribing }

    private var mode: Mode {
        switch app.phase {
        case .recording: return .recording
        case .transcribing: return .transcribing
        default: return .idle
        }
    }

    private let barColor = Color(red: 0.78, green: 0.71, blue: 0.98)

    var body: some View {
        ZStack {
            switch mode {
            case .idle:
                idleContent
            case .recording:
                waveform
            case .transcribing:
                loadingDots
            }
        }
        .frame(width: mode == .idle ? 64 : 180, height: mode == .idle ? 10 : 34)
        .background(.black.opacity(0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mode)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 2)
        .allowsHitTesting(false)
    }

    private var idleContent: some View {
        Capsule()
            .fill(.white.opacity(0.35))
            .frame(width: 28, height: 3)
    }

    private var waveform: some View {
        HStack(spacing: 2.5) {
            ForEach(app.levelHistory.indices, id: \.self) { index in
                Capsule()
                    .fill(barColor)
                    .frame(width: 3, height: 4 + CGFloat(app.levelHistory[index]) * 22)
            }
        }
        .animation(.linear(duration: 0.09), value: app.levelHistory)
    }

    private var loadingDots: some View {
        PulsingDots(color: barColor)
    }
}

private struct PulsingDots: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animating ? 1.0 : 0.45)
                    .opacity(animating ? 1.0 : 0.45)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}
