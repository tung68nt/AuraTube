import SwiftUI
import AppKit

@MainActor
final class PlayerControlViewModel: ObservableObject {
    @Published var isScrubbing: Bool = false {
        didSet {
            if isScrubbing {
                // Safety reset: never let the scrubber stay stuck if drag ends unexpectedly
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    if self?.isScrubbing == true {
                        self?.isScrubbing = false
                    }
                }
            }
        }
    }
    @Published var scrubProgress: Double = 0
    @Published var isBarHovered: Bool = false
    @Published var hoverTime: Double? = nil
    @Published var hoverX: CGFloat = 0
}

/// Fallback glass for systems without Liquid Glass: a see-through blur of what is behind.
private struct PlayerGlassBlur: NSViewRepresentable {
    let opacity: CGFloat
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        view.alphaValue = opacity
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.alphaValue = opacity
    }
}

/// Clear glass in any shape for player chrome: the system Liquid Glass exactly as macOS draws
/// it (its own edge refraction and highlight, nothing layered on top). `tint` is how much black
/// is mixed in so white controls stay readable; `blur` adds a frosted layer under the glass.
struct PlayerGlassShape<S: InsettableShape>: View {
    let shape: S
    var tint: Double = 0.08
    var blur: Double = 0
    
    var body: some View {
        if #available(macOS 26.0, *) {
            ZStack {
                if blur > 0 {
                    PlayerGlassBlur(opacity: blur).clipShape(shape)
                }
                Color.clear
                    .glassEffect(.clear.tint(Color.black.opacity(tint)).interactive(), in: shape)
            }
            // macOS draws glass flatter and more frosted in windows that are not active. Player
            // chrome should look the same whether or not AuraTube is the frontmost app.
            .environment(\.controlActiveState, .key)
        } else {
            PlayerGlassBlur(opacity: min(1.0, 0.45 + blur))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
        }
    }
}

/// Rounded glass panel for player chrome (control bar, mini player toolbar, PiP controls).
struct PlayerGlassBackground: View {
    var cornerRadius: CGFloat = 16
    var tint: Double = 0.08
    var blur: Double = 0
    
    var body: some View {
        PlayerGlassShape(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            blur: blur
        )
    }
}

/// Momentary feedback over the video (play/pause, seek, volume): the glyph in a glass disc,
/// with the label beneath it on the video itself rather than inside a dark box.
struct PlayerHUDBadge: View {
    let icon: String
    let text: String
    var discSize: CGFloat = 54
    
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: discSize * 0.40, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: discSize, height: discSize)
                .background(PlayerGlassShape(shape: Circle(), tint: 0.16))
            
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.55), radius: 0.6, y: 0.5)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

public struct PlayerControlOverlay: View {
    /// Corner radius of the player frame this bar sits in (see NativePlayerView(cornerRadius:)).
    static let playerFrameCornerRadius: CGFloat = 24

    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var speedService = NetworkSpeedService.shared
    @StateObject private var vm = PlayerControlViewModel()
    
    public init() {}
    
    private var effectiveDuration: Double {
        clock.duration > 0 ? clock.duration : playerManager.duration
    }
    
    private var effectiveTime: Double {
        if vm.isScrubbing {
            return vm.scrubProgress * max(1, effectiveDuration)
        }
        return clock.currentTime > 0 ? clock.currentTime : playerManager.currentTime
    }
    
    private var progressRatio: Double {
        let dur = effectiveDuration
        guard dur > 0 else { return 0 }
        if vm.isScrubbing {
            return vm.scrubProgress
        }
        return min(1.0, max(0.0, effectiveTime / dur))
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            GeometryReader { geo in
                let isCompact = geo.size.width < 460 || playerManager.isCurrentVideoVertical
                // Same gap to the left, right and bottom edges of the video, and corners concentric
                // with the player frame's: bar radius = frame radius − gap, both continuous, so
                // the band between the two curves keeps a constant width around the corner.
                let barInset: CGFloat = 10
                let barRadius: CGFloat = Self.playerFrameCornerRadius - barInset
                
                VStack(spacing: isCompact ? 6 : 8) {
                    // 1. Scrubber Timeline Bar (Thanh tua với các phân đoạn)
                    scrubberBar
                        .padding(.horizontal, isCompact ? 8 : 14)
                    
                    // 2. Control Buttons, Chapter title & Time Display
                    controlButtonsRow(isCompact: isCompact)
                        .padding(.horizontal, isCompact ? 8 : 12)
                        .padding(.bottom, 8)
                }
                .padding(.top, 10)
                .environment(\.colorScheme, .dark)
                // Tight + soft shadow pair: glyph edges stay crisp over busy, bright frames
                .shadow(color: .black.opacity(0.45), radius: 0.6, y: 0.5)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .frame(width: max(0, geo.size.width - barInset * 2))
                .background(PlayerGlassBackground(cornerRadius: barRadius))
                .padding(.horizontal, barInset)
                .padding(.bottom, barInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 108)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Scrubber Bar Component
    private var scrubberBar: some View {
        GeometryReader { geo in
            let width = max(10, geo.size.width)
            let trackHeight: CGFloat = vm.isBarHovered || vm.isScrubbing ? 6.5 : 4.0
            
            ZStack(alignment: .leading) {
                // Background Track: segmented if chapters exist, otherwise continuous
                if !playerManager.chapters.isEmpty {
                    segmentedTrack(width: width, trackHeight: trackHeight)
                } else {
                    continuousTrack(width: width, trackHeight: trackHeight)
                }
                
                // Scrubber Knob (Circle indicator)
                Circle()
                    .fill(Color(red: 1.0, green: 0.14, blue: 0.25))
                    .frame(
                        width: vm.isBarHovered || vm.isScrubbing ? 15 : 10,
                        height: vm.isBarHovered || vm.isScrubbing ? 15 : 10
                    )
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    .offset(x: max(0, min(width - 12, (width * CGFloat(progressRatio)) - (vm.isBarHovered || vm.isScrubbing ? 7.5 : 5.0))))
                    .animation(.spring(response: 0.2, dampingFraction: 0.75), value: vm.isBarHovered || vm.isScrubbing)
                
                // Native AppKit Mouse & Trackpad Interactivity Layer (Covers entire 28pt height)
                ScrubberTrackView(
                    onHoverChanged: { isHovered, x in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            vm.isBarHovered = isHovered
                        }
                        if isHovered {
                            vm.hoverX = x
                            let ratio = Double(max(0, min(width, x)) / width)
                            vm.hoverTime = ratio * max(1, playerManager.duration)
                        } else {
                            vm.hoverTime = nil
                        }
                    },
                    onScrubStart: { x in
                        vm.isScrubbing = true
                        let clampedX = max(0, min(width, x))
                        let ratio = Double(clampedX / width)
                        vm.scrubProgress = ratio
                        vm.hoverX = clampedX
                        let targetSec = ratio * max(1, playerManager.duration)
                        vm.hoverTime = targetSec
                        // Immediate seek on touch/mouse-down for zero latency
                        playerManager.seek(to: targetSec)
                    },
                    onScrubUpdate: { x in
                        vm.isScrubbing = true
                        let clampedX = max(0, min(width, x))
                        let ratio = Double(clampedX / width)
                        vm.scrubProgress = ratio
                        vm.hoverX = clampedX
                        let targetSec = ratio * max(1, playerManager.duration)
                        vm.hoverTime = targetSec
                        playerManager.seek(to: targetSec)
                    },
                    onScrubEnd: { x in
                        let clampedX = max(0, min(width, x))
                        let ratio = Double(clampedX / width)
                        let targetSec = ratio * max(1, playerManager.duration)
                        playerManager.seek(to: targetSec)
                        vm.isScrubbing = false
                    }
                )
                .frame(height: 28)
                
                // Hover Time & Chapter Tooltip
                if let ht = vm.hoverTime, vm.isBarHovered && !vm.isScrubbing {
                    let tooltipText: String = {
                        if let ch = playerManager.chapter(at: ht) {
                            return "\(ch.title) • \(formatTime(ht))"
                        }
                        return formatTime(ht)
                    }()
                    
                    Text(tooltipText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.88))
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(x: max(0, min(width - 120, vm.hoverX - 60)), y: -26)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 28)
        }
        .frame(height: 28)
    }
    
    // MARK: - Continuous Track (Standard)
    @ViewBuilder
    private func continuousTrack(width: CGFloat, trackHeight: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Background Track
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(height: trackHeight)
            
            // SponsorBlock Segments Markers
            if playerManager.duration > 0 {
                ForEach(playerManager.sponsorSegments, id: \.start) { seg in
                    let startRatio = max(0, min(1, seg.start / playerManager.duration))
                    let endRatio = max(0, min(1, seg.end / playerManager.duration))
                    let segWidth = max(2.0, (endRatio - startRatio) * width)
                    
                    Capsule()
                        .fill(Color.green.opacity(0.85))
                        .frame(width: segWidth, height: trackHeight)
                        .offset(x: startRatio * width)
                }
            }
            
            // Active Progress (YouTube Red)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.9, green: 0.08, blue: 0.18)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(0, min(width, width * CGFloat(progressRatio))), height: trackHeight)
        }
    }
    
    // MARK: - Segmented Track (With YouTube Chapters)
    @ViewBuilder
    private func segmentedTrack(width: CGFloat, trackHeight: CGFloat) -> some View {
        let chapters = playerManager.chapters
        let gap: CGFloat = 2.5
        let totalGaps = CGFloat(max(0, chapters.count - 1)) * gap
        let availW = max(10, width - totalGaps)
        let totalDur = max(1, playerManager.duration > 0 ? playerManager.duration : (chapters.last?.end ?? 1))
        
        ZStack(alignment: .leading) {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                let dur = max(0.1, chapter.end - chapter.start)
                let segRatio = dur / totalDur
                let segWidth = max(2.0, availW * CGFloat(segRatio))
                
                // Calculate X offset for this segment
                let prevRatioSum = chapters.prefix(index).reduce(0.0) { $0 + max(0.1, $1.end - $1.start) } / totalDur
                let segX = (availW * CGFloat(prevRatioSum)) + (CGFloat(index) * gap)
                
                // Calculate fill width for this chapter segment
                let fillWidth: CGFloat = {
                    if effectiveTime <= chapter.start {
                        return 0
                    } else if effectiveTime >= chapter.end {
                        return segWidth
                    } else {
                        let fillRatio = (effectiveTime - chapter.start) / dur
                        return max(0, min(segWidth, segWidth * CGFloat(fillRatio)))
                    }
                }()
                
                ZStack(alignment: .leading) {
                    // Segment background
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: segWidth, height: trackHeight)
                    
                    // Segment filled progress
                    if fillWidth > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.9, green: 0.08, blue: 0.18)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth, height: trackHeight)
                    }
                }
                .offset(x: segX)
            }
        }
    }
    
    // MARK: - Controls Row
    @ViewBuilder
    private func controlButtonsRow(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 8 : 16) {
            // Play / Pause (ALWAYS PRESENT ON THE LEFT)
            Button(action: { playerManager.togglePlayPause() }) {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
            }
            .buttonStyle(.plain)
            
            if !isCompact {
                // Backward 10s
                Button(action: { playerManager.seekRelative(-10) }) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Tua lùi 10 giây (J)")
                
                // Forward 10s
                Button(action: { playerManager.seekRelative(10) }) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Tua tới 10 giây (L)")
            }
            
            // Volume / Mute (ALWAYS PRESENT)
            Button(action: { playerManager.toggleMute() }) {
                Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : (playerManager.volume > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                    .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: isCompact ? 22 : 26, height: isCompact ? 22 : 26)
            }
            .buttonStyle(.plain)
            .help("Tắt/Bật tiếng (M)")
            
            // Current Time / Total Duration + Chapter Title (ALWAYS PRESENT)
            HStack(spacing: isCompact ? 2.5 : 4) {
                Text(formatTime(effectiveTime))
                    .font(.system(size: isCompact ? 10.5 : 12, weight: .medium).monospacedDigit())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                Text("/")
                    .font(.system(size: isCompact ? 9.5 : 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                Text(formatTime(playerManager.duration))
                    .font(.system(size: isCompact ? 10.5 : 12, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .fixedSize()
                
                // Display Current Chapter Title next to time (like YouTube)
                if !isCompact && !playerManager.isCurrentVideoVertical, let ch = playerManager.currentChapter {
                    Text("•")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 3)
                        .lineLimit(1)
                    Text(ch.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: 240, alignment: .leading)
                        .layoutPriority(-1)
                }
            }
            .lineLimit(1)
            .padding(.leading, isCompact ? 0 : 2)
            
            Spacer(minLength: 4)
            
            // Quality Dropdown Menu (Độ phân giải) (ALWAYS PRESENT)
            Menu {
                // Network Speed Status Header
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                        Text("Tốc độ mạng: \(speedService.displaySpeed)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text("Độ trễ: \(speedService.displayLatency) • \(speedService.statusSummary)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    speedService.measureSpeed(force: true)
                }) {
                    Label(speedService.isTesting ? "Đang đo tốc độ..." : "Kiểm tra lại tốc độ mạng", systemImage: "arrow.clockwise")
                }
                
                Divider()
                
                // Smart Auto Quality Option
                Button(action: { playerManager.setQuality("auto") }) {
                    HStack {
                        let opt = playerManager.resolvedOptimalQuality
                        let optLabel = (opt == "2160") ? "4K" : ((opt == "1440") ? "2K" : "\(opt)p")
                        Text("Tự động (Tối ưu theo mạng -> \(optLabel))")
                        if playerManager.selectedQuality == "auto" {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                // Max Resolution Priority Toggle
                Button(action: {
                    playerManager.preferMaxQuality.toggle()
                }) {
                    HStack {
                        Text("Ưu tiên chất lượng tối đa (Max 4K/2K)")
                        if playerManager.preferMaxQuality {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
                let qualitiesToShow: [String] = {
                    if !playerManager.availableQualities.isEmpty {
                        return playerManager.availableQualities.map { "\($0)" }
                    } else {
                        return ["2160", "1440", "1080", "720", "480", "360"]
                    }
                }()
                
                ForEach(qualitiesToShow, id: \.self) { q in
                    Button(action: { playerManager.setQuality(q) }) {
                        HStack {
                            Text(qualityMenuLabel(q))
                            if playerManager.selectedQuality == q {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: isCompact ? 2 : 3) {
                    Text(displayQualityBadge(isCompact: isCompact))
                        .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: isCompact ? 7 : 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, isCompact ? 5 : 7)
                .padding(.vertical, isCompact ? 3 : 3.5)
                .background(Color.white.opacity(0.18))
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Chọn độ phân giải video")
            
            // Speed Dropdown Menu (Tốc độ phát) (ALWAYS PRESENT)
            Menu {
                ForEach(PlayerManager.availablePlaybackRates, id: \.self) { rate in
                    Button(action: { playerManager.setPlaybackRate(rate) }) {
                        HStack {
                            Text(speedMenuLabel(rate))
                            if abs(playerManager.playbackRate - rate) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: isCompact ? 2 : 3) {
                    Text(displaySpeedBadge)
                        .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: isCompact ? 7 : 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, isCompact ? 5 : 7)
                .padding(.vertical, isCompact ? 3 : 3.5)
                .background(Color.white.opacity(0.18))
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Tốc độ phát video (Shift + < / >)")
            
            if !isCompact {
                // Autoplay Next Video Toggle (YouTube Style)
                Button(action: {
                    playerManager.toggleAutoplay()
                }) {
                    // Compact switch in the bar's own language: solid white knob, track in the
                    // scrubber's red when on and a faint white when off. The knob's glyph takes
                    // the track colour, so on/off reads from colour as well as position.
                    ZStack(alignment: playerManager.isAutoplayEnabled ? .trailing : .leading) {
                        Capsule()
                            .fill(
                                playerManager.isAutoplayEnabled
                                    ? Color(red: 1.0, green: 0.16, blue: 0.27)
                                    : Color.white.opacity(0.24)
                            )
                            .frame(width: 34, height: 18)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                            .overlay(
                                Image(systemName: playerManager.isAutoplayEnabled ? "play.fill" : "pause.fill")
                                    .font(.system(size: 6.5, weight: .black))
                                    .foregroundColor(
                                        playerManager.isAutoplayEnabled
                                            ? Color(red: 1.0, green: 0.16, blue: 0.27)
                                            : Color.black.opacity(0.45)
                                    )
                                    .offset(x: playerManager.isAutoplayEnabled ? 0.5 : 0)
                            )
                            .padding(.horizontal, 2)
                    }
                    .animation(.easeInOut(duration: 0.18), value: playerManager.isAutoplayEnabled)
                }
                .buttonStyle(.plain)
                .help(playerManager.isAutoplayEnabled ? "Tự động phát: Đang BẬT" : "Tự động phát: Đang TẮT")
            }
            
            // Reload / Refresh Video Stream Button (Tải lại video khi bị lag / đứng hình)
            Button(action: {
                playerManager.reloadCurrentVideo()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: isCompact ? 10.5 : 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Tải lại video khi bị lag / đứng hình (R)")
            
            // Picture-in-Picture Button (PiP) (ALWAYS PRESENT)
            Button(action: {
                playerManager.togglePictureInPicture()
            }) {
                Image(systemName: playerManager.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                    .font(.system(size: isCompact ? 10.5 : 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
                    .background(playerManager.isPictureInPictureActive ? Color.red.opacity(0.85) : Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onRightClick {
                NotificationCenter.default.post(name: .showSettingsNotification, object: nil)
            }
            .help(playerManager.isPictureInPictureActive ? "Đưa video về cửa sổ chính (P)" : "Chuyển sang cửa sổ nổi PiP (P)")
            
            // Fullscreen Button (ALWAYS PRESENT ON THE RIGHT)
            Button(action: {
                playerManager.toggleFullscreen()
            }) {
                Image(systemName: playerManager.isVideoFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: isCompact ? 10.5 : 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(playerManager.isVideoFullscreen ? "Thoát toàn màn hình (Esc hoặc F)" : "Toàn màn hình (F)")
        }
    }
    
    private func displayQualityBadge(isCompact: Bool = false) -> String {
        let qToDisplay: String = {
            if playerManager.selectedQuality != "auto" {
                return playerManager.selectedQuality
            }
            if !playerManager.currentQuality.isEmpty && playerManager.currentQuality != "auto" && playerManager.currentQuality != "default" {
                return playerManager.currentQuality
            }
            return playerManager.resolvedOptimalQuality
        }()
        
        let label: String
        switch qToDisplay {
        case "4320": label = "8K"
        case "2880": label = "5K"
        case "2160": label = "4K"
        case "1440": label = "2K"
        case "1080": label = "1080p"
        case "720": label = "720p"
        default: label = "\(qToDisplay)p"
        }
        
        if playerManager.selectedQuality == "auto" {
            return isCompact ? label : "Auto • \(label)"
        } else {
            return label
        }
    }
    
    private var displaySpeedBadge: String {
        let r = playerManager.playbackRate
        if abs(r - 1.0) < 0.01 {
            return "1.0x"
        } else if r == Double(Int(r)) {
            return "\(Int(r))x"
        } else {
            return String(format: "%gx", r)
        }
    }
    
    private func speedMenuLabel(_ rate: Double) -> String {
        if abs(rate - 1.0) < 0.01 {
            return "1.0x (Chuẩn)"
        } else {
            return String(format: "%gx", rate)
        }
    }
    
    private func qualityMenuLabel(_ q: String) -> String {
        switch q {
        case "4320": return "4320p (8K)"
        case "2880": return "2880p"
        case "2160": return "2160p (4K)"
        case "1440": return "1440p (2K)"
        case "1080": return "1080p (Full HD)"
        case "720": return "720p (HD)"
        case "480": return "480p"
        case "360": return "360p"
        case "240": return "240p"
        case "144": return "144p"
        default: return "\(q)p"
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(seconds)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - Native AppKit Scrubber Track Interactivity Layer
struct ScrubberTrackView: NSViewRepresentable {
    let onHoverChanged: (Bool, CGFloat) -> Void
    let onScrubStart: (CGFloat) -> Void
    let onScrubUpdate: (CGFloat) -> Void
    let onScrubEnd: (CGFloat) -> Void
    
    func makeNSView(context: Context) -> ScrubberNSView {
        let view = ScrubberNSView()
        view.onHoverChanged = onHoverChanged
        view.onScrubStart = onScrubStart
        view.onScrubUpdate = onScrubUpdate
        view.onScrubEnd = onScrubEnd
        return view
    }
    
    func updateNSView(_ nsView: ScrubberNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.onScrubStart = onScrubStart
        nsView.onScrubUpdate = onScrubUpdate
        nsView.onScrubEnd = onScrubEnd
    }
}

final class ScrubberNSView: NSView {
    var onHoverChanged: ((Bool, CGFloat) -> Void)?
    var onScrubStart: ((CGFloat) -> Void)?
    var onScrubUpdate: ((CGFloat) -> Void)?
    var onScrubEnd: ((CGFloat) -> Void)?
    
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHoverChanged?(true, max(0, min(bounds.width, point.x)))
    }
    
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHoverChanged?(true, max(0, min(bounds.width, point.x)))
    }
    
    override func mouseExited(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHoverChanged?(false, max(0, min(bounds.width, point.x)))
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clampedX = max(0, min(bounds.width, point.x))
        onScrubStart?(clampedX)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clampedX = max(0, min(bounds.width, point.x))
        onScrubUpdate?(clampedX)
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clampedX = max(0, min(bounds.width, point.x))
        onScrubEnd?(clampedX)
    }
}
