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

public struct PlayerControlOverlay: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @StateObject private var vm = PlayerControlViewModel()
    
    public init() {}
    
    private var effectiveTime: Double {
        if vm.isScrubbing {
            return vm.scrubProgress * max(1, playerManager.duration)
        }
        return playerManager.currentTime
    }
    
    private var progressRatio: Double {
        guard playerManager.duration > 0 else { return 0 }
        if vm.isScrubbing {
            return vm.scrubProgress
        }
        return min(1.0, max(0.0, playerManager.currentTime / playerManager.duration))
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 8) {
                // 1. Scrubber Timeline Bar (Thanh tua với các phân đoạn)
                scrubberBar
                    .padding(.horizontal, 14)
                
                // 2. Control Buttons, Chapter title & Time Display
                controlButtonsRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .padding(.top, 16)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.55), location: 0.25),
                        .init(color: Color.black.opacity(0.92), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
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
    private var controlButtonsRow: some View {
        HStack(spacing: 16) {
            // Play / Pause
            Button(action: { playerManager.togglePlayPause() }) {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            
            // Backward 10s
            Button(action: { playerManager.seekRelative(-10) }) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(white: 0.9))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Tua lùi 10 giây (J)")
            
            // Forward 10s
            Button(action: { playerManager.seekRelative(10) }) {
                Image(systemName: "goforward.10")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(white: 0.9))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Tua tới 10 giây (L)")
            
            // Volume / Mute
            Button(action: { playerManager.toggleMute() }) {
                Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : (playerManager.volume > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.9))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Tắt/Bật tiếng (M)")
            
            // Current Time / Total Duration + Chapter Title
            HStack(spacing: 4) {
                Text(formatTime(effectiveTime))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Text("/")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(white: 0.5))
                Text(formatTime(playerManager.duration))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.7))
                
                // Display Current Chapter Title next to time (like YouTube)
                if let ch = playerManager.currentChapter {
                    Text("•")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(white: 0.4))
                        .padding(.horizontal, 3)
                    Text(ch.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(white: 0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 260, alignment: .leading)
                }
            }
            .padding(.leading, 2)
            
            Spacer()
            
            // Quality Dropdown Menu (Độ phân giải)
            Menu {
                Button(action: { playerManager.setQuality("auto") }) {
                    HStack {
                        Text("Tự động (Auto)")
                        if playerManager.selectedQuality == "auto" {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
                let qualitiesToShow: [String] = {
                    if !playerManager.availableQualities.isEmpty {
                        return playerManager.availableQualities.map { "\($0)" }
                    } else {
                        return ["1080", "720", "480", "360"]
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
                HStack(spacing: 3) {
                    Text(displayQualityBadge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(Color(white: 0.7))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.18))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Chọn độ phân giải video")
            
            // Autoplay Next Video Toggle (YouTube Style)
            Button(action: {
                playerManager.toggleAutoplay()
            }) {
                ZStack(alignment: playerManager.isAutoplayEnabled ? .trailing : .leading) {
                    Capsule()
                        .fill(playerManager.isAutoplayEnabled ? Color.white : Color(white: 0.28))
                        .frame(width: 32, height: 16)
                    
                    Circle()
                        .fill(playerManager.isAutoplayEnabled ? Color.black : Color(white: 0.75))
                        .frame(width: 12, height: 12)
                        .padding(.horizontal, 2)
                        .overlay(
                            Image(systemName: playerManager.isAutoplayEnabled ? "play.fill" : "pause.fill")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(playerManager.isAutoplayEnabled ? .white : .black)
                        )
                }
                .animation(.easeInOut(duration: 0.18), value: playerManager.isAutoplayEnabled)
            }
            .buttonStyle(.plain)
            .help(playerManager.isAutoplayEnabled ? "Tự động phát: Đang BẬT" : "Tự động phát: Đang TẮT")
            
            // Fullscreen Button
            Button(action: {
                print("### [PlayerControlOverlay] Fullscreen button CLICKED!")
                playerManager.toggleFullscreen()
            }) {
                Image(systemName: playerManager.isVideoFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(playerManager.isVideoFullscreen ? "Thoát toàn màn hình (Esc hoặc F)" : "Toàn màn hình (F)")
        }
    }
    
    private var displayQualityBadge: String {
        if playerManager.selectedQuality != "auto" {
            return "\(playerManager.selectedQuality)p"
        } else if !playerManager.currentQuality.isEmpty && playerManager.currentQuality != "auto" && playerManager.currentQuality != "default" {
            return "Auto • \(playerManager.currentQuality)p"
        } else {
            return "Auto"
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
