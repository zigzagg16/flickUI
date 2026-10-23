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
    /// Small frames for motion analysis, alongside what the player shows.
    @State private var videoOutput: AVPlayerItemVideoOutput?
    @State private var motionAnalyzer = MotionAnalyzer()
    @State private var motion: MotionReading?
    @AppStorage("analyzesLiveMotion") private var analyzesMotion = true

    /// The time between the two frames compared: short enough for optical flow to
    /// follow a vehicle from one to the other.
    private static let frameGap = Duration.milliseconds(200)
    private static let motionInterval = Duration.seconds(2)

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
            .overlay(alignment: .bottomTrailing) {
                if let motion, isPlaying, !failed {
                    MotionBadge(reading: motion)
                        .padding()
                }
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
            .task(id: "\(motorway.id)-\(attempt)-\(analyzesMotion)") {
                await measureMotion()
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
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 180
        ])
        item.add(output)
        videoOutput = output
        player.replaceCurrentItem(with: item)
        player.play()
        for await status in item.publisher(for: \.status).values where status == .failed {
            failed = true
            break
        }
    }

    /// Compares two frames a moment apart every few seconds while the stream plays.
    private func measureMotion() async {
        motion = nil
        guard analyzesMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.motionInterval)
            guard isPlaying, let first = currentFrame() else { continue }
            try? await Task.sleep(for: Self.frameGap)
            guard let second = currentFrame() else { continue }
            if let reading = await motionAnalyzer.motion(from: first, to: second), !Task.isCancelled {
                withAnimation(.smooth) { motion = reading }
            }
        }
    }

    private func currentFrame() -> VideoFrame? {
        videoOutput?
            .copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil)
            .map(VideoFrame.init)
    }
}

/// The movement on each carriageway of the live stream.
struct MotionBadge: View {
    let reading: MotionReading

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            side("Left", reading.left)
            side("Right", reading.right)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func side(_ name: String, _ value: Double) -> some View {
        HStack(spacing: 6) {
            Text("\(name): \(MotionReading.level(value).title)")
            Gauge(value: value) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(value < 0.15 ? .red : value < 0.5 ? .orange : .green)
            .frame(width: 44)
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
