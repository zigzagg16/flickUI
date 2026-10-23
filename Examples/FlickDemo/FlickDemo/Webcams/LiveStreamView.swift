import AVFoundation
import AVKit
import Combine
import SwiftUI
import WebcamsCore
import WebcamsVision

/// A motorway's live stream, muted on start like on cita.lu.
struct LiveStreamView: View {
    let motorway: Motorway

    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var failed = false
    @State private var attempt = 0
    /// Small frames for motion analysis, alongside what the player shows.
    @State private var videoOutput: AVPlayerItemVideoOutput?
    @State private var motionAnalyzer = MotionAnalyzer()
    @State private var motion: MotionReading?
    /// The camera the stream shows now, read from the picture.
    @State private var liveCamera: LiveCamera?
    @AppStorage("analyzesLiveMotion") private var analyzesMotion = true
    /// Every camera the stream showed, with its last frames.
    @State private var dashboard: [CameraSnapshot] = []
    @State private var showsDashboard = false

    /// The time between the two frames compared: short enough for optical flow to
    /// follow a vehicle from one to the other.
    private static let frameGap = Duration.milliseconds(150)
    /// The pause between looks: streams show each camera for a couple of seconds, so
    /// looks come often enough for several readings per camera.
    private static let motionInterval = Duration.milliseconds(400)

    var body: some View {
        VStack(spacing: 0) {
            playerView
                .frame(maxHeight: showsDashboard ? 200 : .infinity)
            if showsDashboard {
                LiveDashboard(snapshots: dashboard, currentLabel: liveCamera?.label)
            }
        }
        // Clear of the screen's header while the dashboard shows.
        .padding(.top, showsDashboard ? 150 : 0)
        .animation(.smooth, value: showsDashboard)
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

    private var playerView: some View {
        VideoPlayer(player: player)
            // No playback controls: every touch reaches the menus.
            .allowsHitTesting(false)
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
                HStack {
                    if analyzesMotion {
                        Button {
                            showsDashboard.toggle()
                        } label: {
                            Image(systemName: showsDashboard ? "rectangle.fill" : "square.grid.2x2.fill")
                                .contentTransition(.symbolEffect(.replace))
                                .roundButton()
                        }
                        .accessibilityLabel(showsDashboard ? "Hide Dashboard" : "Show Dashboard")
                    }
                }
                .padding(showsDashboard ? 8 : 16)
            }
            .overlay(alignment: .bottomTrailing) {
                if isPlaying, !failed, !showsDashboard, motion != nil || liveCamera != nil {
                    MotionBadge(camera: liveCamera, reading: motion)
                        .padding()
                }
            }
    }

    private func play() async {
        failed = false
        guard let stream = motorway.liveStream else {
            failed = true
            return
        }
        // The streams have no sound.
        player.isMuted = true
        let url = stream.url
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            // Large enough to read the camera label burnt into the picture.
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 360
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
        liveCamera = nil
        dashboard = []
        await motionAnalyzer.resetDashboard()
        guard analyzesMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.motionInterval)
            guard isPlaying, let first = currentFrame() else { continue }
            try? await Task.sleep(for: Self.frameGap)
            guard let second = currentFrame() else { continue }
            let reading = await motionAnalyzer.analyze(from: first, to: second)
            let snapshots = await motionAnalyzer.dashboard()
            guard !Task.isCancelled else { return }
            dashboard = snapshots
            withAnimation(.smooth) {
                liveCamera = reading.camera
                // A new camera starts over; a cut alone keeps the last reading.
                // A camera seen before shows its last reading, marked as such, until
                // a new one comes in.
                if let measured = reading.motion {
                    motion = measured
                } else if reading.cameraChanged {
                    motion = reading.previousVisit
                }
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
    let camera: LiveCamera?
    let reading: MotionReading?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let camera {
                if let caption = camera.caption {
                    Text(caption)
                        .lineLimit(1)
                }
                Text(camera.label)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let reading {
                Group {
                    side("Left", reading.left)
                    side("Right", reading.right)
                }
                .opacity(reading.isFromEarlierVisit ? 0.5 : 1)
                if reading.isFromEarlierVisit {
                    Text("Seen \(reading.measuredAt, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Measuring…")
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func side(_ name: String, _ value: Double) -> some View {
        MotionSide(name: name, value: value)
    }
}

/// The movement on one carriageway, in words and as a gauge.
struct MotionSide: View {
    let name: String
    let value: Double

    var body: some View {
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

/// Every camera the live stream showed, side by side, each replaying its last frames.
/// A camera's tile is as recent as the stream's last visit to it.
struct LiveDashboard: View {
    let snapshots: [CameraSnapshot]
    /// The camera on screen now.
    let currentLabel: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                ForEach(snapshots) { snapshot in
                    CameraTile(snapshot: snapshot, isCurrent: snapshot.id == currentLabel)
                }
            }
            .padding(8)
        }
        .overlay {
            if snapshots.isEmpty {
                ContentUnavailableView(
                    "Collecting Cameras",
                    systemImage: "square.grid.2x2",
                    description: Text("Each camera appears here as the stream shows it.")
                )
            }
        }
    }
}

struct CameraTile: View {
    let snapshot: CameraSnapshot
    let isCurrent: Bool

    /// How long each kept frame shows in the tile's loop.
    private static let frameDuration: TimeInterval = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: Self.frameDuration)) { context in
                if !snapshot.frames.isEmpty {
                    let step = Int(context.date.timeIntervalSinceReferenceDate / Self.frameDuration)
                    Image(decorative: snapshot.frames[step % snapshot.frames.count].image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.gray.opacity(0.3)
                        .aspectRatio(16 / 9, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isCurrent ? Color.yellow : .clear, lineWidth: 2)
            }
            Text(snapshot.camera.caption ?? snapshot.camera.label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            HStack {
                Text(snapshot.camera.label)
                    .font(.caption2.monospaced())
                Spacer()
                if isCurrent {
                    Text("Live")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                } else {
                    Text(snapshot.lastSeen, style: .relative)
                        .font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(.secondary)
            if let motion = snapshot.motion {
                Group {
                    MotionSide(name: "L", value: motion.left)
                    MotionSide(name: "R", value: motion.right)
                }
                .font(.caption2)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func roundButton() -> some View {
        frame(width: 24, height: 24)
            .padding(10)
            .background(.ultraThinMaterial, in: Circle())
    }
}
