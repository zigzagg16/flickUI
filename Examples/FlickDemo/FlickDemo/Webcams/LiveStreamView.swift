import AVFoundation
import Combine
import SwiftUI
import UIKit

/// A motorway's live stream, muted on start like on cita.lu.
struct LiveStreamView: View {
    let motorway: Motorway

    @State private var player = AVPlayer()
    @State private var isMuted = true
    @State private var isPlaying = false
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        PlayerLayerView(player: player)
            .overlay {
                if failed {
                    ContentUnavailableView {
                        Label("Live stream unavailable", systemImage: "play.slash.fill")
                    } actions: {
                        Button("Try Again") { attempt += 1 }
                    }
                } else if !isPlaying {
                    ProgressView()
                }
            }
            .overlay(alignment: .bottomLeading) {
                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24, height: 24)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                .padding()
            }
            .onChange(of: isMuted, initial: true) { _, muted in
                player.isMuted = muted
            }
            .onReceive(player.publisher(for: \.timeControlStatus).receive(on: DispatchQueue.main)) { status in
                isPlaying = status == .playing
            }
            .task(id: "\(motorway.id)-\(attempt)") {
                await play()
            }
            .onDisappear {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
    }

    private func play() async {
        failed = false
        let url = await CitaWebcams.liveStream(for: motorway)
        guard !Task.isCancelled else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        for await status in item.publisher(for: \.status).values where status == .failed {
            failed = true
            break
        }
    }
}

/// An `AVPlayerLayer` without playback controls, so every touch reaches the menus.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}
