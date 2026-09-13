import SwiftUI
import AppKit

@MainActor
final class NativeShortsViewModel: ObservableObject {
    @Published var shorts: [Video] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var continuationToken: String? = nil
    @Published var likedShorts: Set<String> = []
    @Published var dislikedShorts: Set<String> = []
    @Published var subscribedChannels: Set<String> = []
    @Published var toastMessage: String? = nil
    
    private let queryPool = [
        "#shorts việt nam",
        "#shorts trending",
        "#shorts hài hước",
        "#shorts ca nhạc",
        "#shorts khám phá"
    ]
    private var poolIndex = 0
    
    func openShort(_ video: Video) {
        if let idx = shorts.firstIndex(where: { $0.id == video.id }) {
            currentIndex = idx
            playCurrentShort()
        } else {
            shorts.insert(video, at: 0)
            currentIndex = 0
            playCurrentShort()
            if shorts.count <= 2 {
                Task {
                    let related = await YTDLPService.shared.searchVideos(query: "#shorts " + video.uploader, limit: 12)
                    let newShorts = related.filter { s in !self.shorts.contains(where: { $0.id == s.id }) }
                    self.shorts.append(contentsOf: newShorts)
                    if self.shorts.count < 5 {
                        await self.loadMoreShorts()
                    }
                }
            }
        }
    }
    
    func loadInitialShorts(preferredInitial: Video? = nil) async {
        if let initial = preferredInitial, shorts.isEmpty {
            shorts = [initial]
            currentIndex = 0
            playCurrentShort()
        }
        guard shorts.count <= 1 else { return }
        isLoading = true
        
        let result = await YTDLPService.shared.searchVideosWithContinuation(query: "#shorts việt nam")
        var loaded = result.shorts
        if loaded.isEmpty {
            loaded = result.videos.filter { ($0.duration ?? 0) <= 65 }
        }
        if loaded.isEmpty {
            loaded = await YTDLPService.shared.searchVideos(query: "#shorts trending", limit: 20)
        }
        
        let existingIds = Set(self.shorts.map { $0.id })
        let filtered = loaded.filter { !existingIds.contains($0.id) }
        self.shorts.append(contentsOf: filtered)
        self.continuationToken = result.continuationToken
        self.isLoading = false
        
        if self.currentIndex == 0 && preferredInitial == nil, let first = self.shorts.first {
            playShort(first)
        }
    }
    
    func loadMoreShorts() async {
        guard !isLoading else { return }
        isLoading = true
        
        var newShorts: [Video] = []
        if let token = continuationToken {
            let res = await YTDLPService.shared.searchVideosWithContinuation(query: "#shorts việt nam", continuationToken: token)
            newShorts = res.shorts.isEmpty ? res.videos.filter { ($0.duration ?? 0) <= 65 } : res.shorts
            self.continuationToken = res.continuationToken
        }
        
        if newShorts.isEmpty {
            poolIndex = (poolIndex + 1) % queryPool.count
            let fallbackQuery = queryPool[poolIndex]
            newShorts = await YTDLPService.shared.searchVideos(query: fallbackQuery, limit: 16)
        }
        
        let existingIds = Set(self.shorts.map { $0.id })
        let filtered = newShorts.filter { !existingIds.contains($0.id) }
        self.shorts.append(contentsOf: filtered)
        self.isLoading = false
    }
    
    func goToNext() {
        guard currentIndex < shorts.count - 1 else { return }
        currentIndex += 1
        playCurrentShort()
        if currentIndex >= shorts.count - 3 {
            Task { await loadMoreShorts() }
        }
    }
    
    func goToPrev() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        playCurrentShort()
    }
    
    func playCurrentShort() {
        guard currentIndex >= 0 && currentIndex < shorts.count else { return }
        let current = shorts[currentIndex]
        playShort(current)
    }
    
    private func playShort(_ video: Video) {
        PlayerManager.shared.loadAndPlay(video: video)
    }
    
    private var lastScrollDate: Date = Date()
    private var eventMonitor: Any? = nil
    
    func startScrollMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            let delta = event.scrollingDeltaY
            let now = Date()
            if abs(delta) > 12 && now.timeIntervalSince(self.lastScrollDate) > 0.35 {
                self.lastScrollDate = now
                if delta < 0 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        self.goToNext()
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        self.goToPrev()
                    }
                }
            }
            return event
        }
    }
    
    func stopScrollMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

public struct NativeShortsFeedView: View {
    @Binding var selectedShort: Video?
    var onSelectVideo: (Video) -> Void
    @StateObject private var vm = NativeShortsViewModel()
    @ObservedObject private var playerManager = PlayerManager.shared
    
    public init(selectedShort: Binding<Video?> = .constant(nil), onSelectVideo: @escaping (Video) -> Void) {
        self._selectedShort = selectedShort
        self.onSelectVideo = onSelectVideo
    }
    
    public var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            
            if vm.isLoading && vm.shorts.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Đang tải YouTube Shorts...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(white: 0.65))
                }
            } else if vm.shorts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "play.square.stack")
                        .font(.system(size: 40))
                        .foregroundColor(Color(white: 0.4))
                    Text("Không tìm thấy Shorts nào")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(white: 0.7))
                    Button("Thử lại") {
                        Task { await vm.loadInitialShorts() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 24) {
                    Spacer()
                    
                    // Main 9:16 Portrait Short Card
                    if vm.currentIndex >= 0 && vm.currentIndex < vm.shorts.count {
                        let currentShort = vm.shorts[vm.currentIndex]
                        
                        ZStack(alignment: .bottom) {
                            // Video Player / Thumbnail View
                            ZStack {
                                if playerManager.currentVideo?.id == currentShort.id {
                                    NativePlayerView()
                                        .frame(width: 380, height: 675)
                                        .clipped()
                                } else {
                                    AsyncImage(url: URL(string: currentShort.thumbnail)) { phase in
                                        if let img = phase.image {
                                            img.resizable().scaledToFill()
                                        } else {
                                            Color.black
                                        }
                                    }
                                    .frame(width: 380, height: 675)
                                    .clipped()
                                    
                                    ProgressView()
                                        .controlSize(.regular)
                                }
                            }
                            .frame(width: 380, height: 675)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 10)
                            
                            // Top Bar inside Video: Short Counter Badge + Sound Mute Button
                            VStack {
                                HStack {
                                    HStack(spacing: 5) {
                                        Image(systemName: "flame.fill")
                                            .foregroundColor(.red)
                                            .font(.system(size: 11))
                                        Text("Short \(vm.currentIndex + 1)/\(max(1, vm.shorts.count))")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.75))
                                    .padding([.top, .leading], 14)
                                    
                                    Spacer()
                                    
                                    Button(action: { playerManager.isMuted.toggle() }) {
                                        Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(width: 34, height: 34)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding([.top, .trailing], 14)
                                }
                                Spacer()
                            }
                            .frame(width: 380, height: 675)
                            
                            // Bottom Overlay Metadata
                            VStack(alignment: .leading, spacing: 10) {
                                // Channel Info Row
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(LinearGradient(colors: [Color.red.opacity(0.8), Color.purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Text(String(currentShort.uploader.prefix(1)).uppercased())
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                    
                                    Text(currentShort.uploader)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    // Subscribe button
                                    let isSub = vm.subscribedChannels.contains(currentShort.uploader)
                                    Button(action: {
                                        if isSub {
                                            vm.subscribedChannels.remove(currentShort.uploader)
                                            vm.showToast("Đã hủy đăng ký kênh: \(currentShort.uploader)")
                                        } else {
                                            vm.subscribedChannels.insert(currentShort.uploader)
                                            vm.showToast("🔔 Đã đăng ký kênh: \(currentShort.uploader)")
                                        }
                                    }) {
                                        Text(isSub ? "Đã đăng ký" : "Đăng ký")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(isSub ? .white : .black)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 5)
                                            .background(isSub ? Color.white.opacity(0.25) : Color.white)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // Short Title
                                Text(currentShort.title)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundColor(Color(white: 0.95))
                                    .lineLimit(2)
                                    .lineSpacing(2)
                                
                                // Sound Row
                                HStack(spacing: 6) {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 11))
                                    Text("Âm thanh gốc - \(currentShort.uploader)")
                                        .font(.system(size: 11.5))
                                        .lineLimit(1)
                                }
                                .foregroundColor(Color.white.opacity(0.8))
                            }
                            .padding(16)
                            .frame(width: 380)
                            .background(
                                LinearGradient(
                                    colors: [Color.clear, Color.black.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .gesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { val in
                                    if val.translation.height < -40 {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            vm.goToNext()
                                        }
                                    } else if val.translation.height > 40 {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            vm.goToPrev()
                                        }
                                    }
                                }
                        )
                        
                        // Right Side Action Buttons
                        VStack(spacing: 16) {
                            Spacer()
                            
                            // Like Button
                            let isLiked = vm.likedShorts.contains(currentShort.id)
                            ActionButton(
                                icon: "hand.thumbsup.fill",
                                label: isLiked ? "Đã thích" : (currentShort.viewCountFormatted.isEmpty ? "Thích" : currentShort.viewCountFormatted),
                                isActive: isLiked,
                                activeColor: .red
                            ) {
                                if isLiked {
                                    vm.likedShorts.remove(currentShort.id)
                                } else {
                                    vm.likedShorts.insert(currentShort.id)
                                    vm.dislikedShorts.remove(currentShort.id)
                                    vm.showToast("👍 Đã thích Short!")
                                }
                            }
                            
                            // Dislike Button
                            let isDisliked = vm.dislikedShorts.contains(currentShort.id)
                            ActionButton(
                                icon: "hand.thumbsdown.fill",
                                label: "Không thích",
                                isActive: isDisliked,
                                activeColor: .gray
                            ) {
                                if isDisliked {
                                    vm.dislikedShorts.remove(currentShort.id)
                                } else {
                                    vm.dislikedShorts.insert(currentShort.id)
                                    vm.likedShorts.remove(currentShort.id)
                                }
                            }
                            
                            // Share Button
                            ActionButton(
                                icon: "arrowshape.turn.up.right.fill",
                                label: "Chia sẻ",
                                isActive: false,
                                activeColor: .white
                            ) {
                                let url = "https://www.youtube.com/shorts/\(currentShort.id)"
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                                vm.showToast("🔗 Đã sao chép liên kết Short!")
                            }
                            
                            // Full Player Button
                            ActionButton(
                                icon: "arrow.up.left.and.arrow.down.right",
                                label: "Xem đủ",
                                isActive: false,
                                activeColor: .white
                            ) {
                                onSelectVideo(currentShort)
                            }
                        }
                        .padding(.bottom, 24)
                        
                        // Right Side Up/Down Navigation Arrows (Desktop Floating Controls)
                        VStack(spacing: 14) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    vm.goToPrev()
                                }
                            }) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(vm.currentIndex > 0 ? .white : Color(white: 0.3))
                                    .frame(width: 46, height: 46)
                                    .background(Color(white: 0.18).opacity(0.85))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.currentIndex <= 0)
                            .help("Short trước (Mũi tên lên)")
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    vm.goToNext()
                                }
                            }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(vm.currentIndex < vm.shorts.count - 1 ? .white : Color(white: 0.3))
                                    .frame(width: 46, height: 46)
                                    .background(Color(white: 0.18).opacity(0.85))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.currentIndex >= vm.shorts.count - 1)
                            .help("Short tiếp theo (Mũi tên xuống)")
                        }
                        .padding(.leading, 12)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 20)
            }
            
            // Toast Notification Overlay
            if let toast = vm.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.16).opacity(0.95))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 4)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // Hidden Keyboard Shortcuts for Navigation
            Group {
                Button("") {
                    withAnimation { vm.goToNext() }
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                .opacity(0)
                
                Button("") {
                    withAnimation { vm.goToPrev() }
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                .opacity(0)
                
                Button("") {
                    PlayerManager.shared.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            if let initial = selectedShort {
                vm.openShort(initial)
            }
            vm.startScrollMonitor()
        }
        .onDisappear {
            vm.stopScrollMonitor()
        }
        .onChange(of: selectedShort) { newShort in
            if let s = newShort {
                vm.openShort(s)
            }
        }
        .task {
            await vm.loadInitialShorts(preferredInitial: selectedShort)
        }
    }
}

private struct ActionButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isActive ? activeColor : .white)
                    .frame(width: 44, height: 44)
                    .background(Color(white: 0.18).opacity(0.85))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color(white: 0.85))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
