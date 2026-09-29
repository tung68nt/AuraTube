import Foundation
import Network
import Combine

/// Network speed tiers representing video streaming resolution capabilities
public enum NetworkSpeedTier: String, CaseIterable, Identifiable {
    case ultra = "4K Ultra HD (≥ 25 Mbps)"
    case veryHigh = "2K Quad HD (≥ 15 Mbps)"
    case high = "1080p Full HD (≥ 6 Mbps)"
    case medium = "720p HD (≥ 3 Mbps)"
    case low = "SD 360p / 480p (< 3 Mbps)"
    
    public var id: String { rawValue }
    
    public var badge: String {
        switch self {
        case .ultra: return "4K"
        case .veryHigh: return "2K"
        case .high: return "1080p"
        case .medium: return "720p"
        case .low: return "SD"
        }
    }
    
    public var targetResolution: String {
        switch self {
        case .ultra: return "2160"
        case .veryHigh: return "1440"
        case .high: return "1080"
        case .medium: return "720"
        case .low: return "480"
        }
    }
}

/// Service to monitor network connectivity, measure download bandwidth, and calculate optimal video resolution
public final class NetworkSpeedService: ObservableObject {
    public static let shared = NetworkSpeedService()
    
    @Published public var currentSpeedMbps: Double = 65.0
    @Published public var latencyMs: Double = 12.0
    @Published public var isTesting: Bool = false
    @Published public var lastTestDate: Date? = nil
    @Published public var networkTier: NetworkSpeedTier = .ultra
    @Published public var isConnected: Bool = true
    @Published public var connectionType: String = "Wi-Fi"
    
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "app.auratube.networkmonitor", qos: .background)
    private var lastTestTimestamp: TimeInterval = 0
    private var cancellables = Set<AnyCancellable>()
    
    // Test endpoints (Cloudflare global edge CDN & fallback)
    private let speedTestEndpoint = URL(string: "https://speed.cloudflare.com/__down?bytes=1048576")! // 1 MB chunk
    private let pingEndpoint = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
    private let fallbackEndpoint = URL(string: "https://www.google.com/generate_204")!
    
    private init() {
        startPathMonitor()
        // Run initial non-blocking speed assessment on background
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.measureSpeed(force: true)
        }
        
        // Re-check periodically every 4 minutes in background
        Timer.publish(every: 240, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.measureSpeed(force: false)
            }
            .store(in: &cancellables)
    }
    
    deinit {
        pathMonitor.cancel()
    }
    
    // MARK: - NWPathMonitor
    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let isConn = (path.status == .satisfied)
            let connType: String
            if path.usesInterfaceType(.wifi) {
                connType = "Wi-Fi"
            } else if path.usesInterfaceType(.wiredEthernet) {
                connType = "Ethernet"
            } else if path.usesInterfaceType(.cellular) {
                connType = "Cellular"
            } else {
                connType = "Mạng dây / Wi-Fi"
            }
            
            DispatchQueue.main.async {
                self.isConnected = isConn
                self.connectionType = connType
            }
            
            // If network restored or switched, re-evaluate speed after brief delay
            let uptime = ProcessInfo.processInfo.systemUptime
            if isConn && (uptime - self.lastTestTimestamp > 15) {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                    self.measureSpeed(force: true)
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }
    
    // MARK: - Speed Measurement
    public func measureSpeed(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && (now - lastTestTimestamp < 60) {
            return // Skip if tested less than 60s ago
        }
        if isTesting { return }
        
        DispatchQueue.main.async {
            self.isTesting = true
        }
        self.lastTestTimestamp = now
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            // 1. Measure Latency Ping
            var measuredLatency: Double = 15.0
            let pingStart = CFAbsoluteTimeGetCurrent()
            var pingReq = URLRequest(url: self.pingEndpoint)
            pingReq.httpMethod = "HEAD"
            pingReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            pingReq.timeoutInterval = 2.5
            
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4.0
            config.timeoutIntervalForResource = 5.0
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let session = URLSession(configuration: config)
            
            if let (_, resp) = try? await session.data(for: pingReq), (resp as? HTTPURLResponse)?.statusCode == 200 {
                let pingTime = CFAbsoluteTimeGetCurrent() - pingStart
                measuredLatency = max(3.0, pingTime * 1000.0)
            }
            
            // 2. Measure Throughput Chunk (1MB payload)
            var downloadReq = URLRequest(url: self.speedTestEndpoint)
            downloadReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            downloadReq.timeoutInterval = 4.0
            
            let speedStart = CFAbsoluteTimeGetCurrent()
            do {
                let (data, resp) = try await session.data(for: downloadReq)
                let elapsed = max(0.02, CFAbsoluteTimeGetCurrent() - speedStart)
                
                if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200, data.count > 10000 {
                    let bytes = Double(data.count)
                    let mbps = (bytes * 8.0) / (elapsed * 1_000_000.0)
                    
                    let finalLatency = measuredLatency
                    await MainActor.run {
                        self.applySpeedResult(mbps: mbps, latency: finalLatency)
                    }
                    return
                }
            } catch {
                // Endpoint might be blocked or connection slow; try small fallback test
            }
            
            // Fallback probe
            let fallbackStart = CFAbsoluteTimeGetCurrent()
            let fbReq = URLRequest(url: self.fallbackEndpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 3.0)
            if let (_, _) = try? await session.data(for: fbReq) {
                let fbElapsed = CFAbsoluteTimeGetCurrent() - fallbackStart
                // On healthy desktop connection, fallback ping < 200ms represents solid broadband
                let estimatedMbps: Double = fbElapsed < 0.2 ? 60.0 : (fbElapsed < 0.5 ? 30.0 : 15.0)
                await MainActor.run {
                    self.applySpeedResult(mbps: estimatedMbps, latency: fbElapsed * 1000.0)
                }
            } else {
                // In offline or edge cases, retain safe high baseline so user isn't stuck at 360p
                await MainActor.run {
                    self.isTesting = false
                }
            }
        }
    }
    
    @MainActor
    private func applySpeedResult(mbps: Double, latency: Double) {
        self.isTesting = false
        self.lastTestDate = Date()
        self.latencyMs = latency
        
        // Smooth speed with exponential moving average to avoid transient degradation
        let smoothed: Double
        if self.currentSpeedMbps > 0 {
            smoothed = (0.75 * mbps) + (0.25 * self.currentSpeedMbps)
        } else {
            smoothed = mbps
        }
        self.currentSpeedMbps = max(2.0, smoothed)
        
        // Classify Network Tier
        if self.currentSpeedMbps >= 22.0 {
            self.networkTier = .ultra
        } else if self.currentSpeedMbps >= 13.0 {
            self.networkTier = .veryHigh
        } else if self.currentSpeedMbps >= 5.5 {
            self.networkTier = .high
        } else if self.currentSpeedMbps >= 2.5 {
            self.networkTier = .medium
        } else {
            self.networkTier = .low
        }
        
        // Trigger PlayerManager to re-check optimal quality if on Auto
        PlayerManager.shared.reevaluateAndApplyOptimalQuality()
    }
    
    // MARK: - Quality Resolution Engine
    /// Determines the best resolution (height: 2160, 1440, 1080, 720, etc.) supported by the network and video
    public func recommendedQuality(from availableQualities: [Int], preferMax: Bool = false) -> String {
        let sorted = availableQualities.sorted(by: >)
        
        // If available qualities not yet loaded from yt-dlp or iframe, return crisp 1080p target
        if sorted.isEmpty {
            if currentSpeedMbps >= 35.0 && preferMax {
                return "2160"
            } else if currentSpeedMbps >= 20.0 && preferMax {
                return "1440"
            } else {
                return "1080"
            }
        }
        
        // 1. Check for 4K (2160p) - Only if speed genuinely supports it without stuttering
        if sorted.contains(where: { $0 >= 2160 }) {
            if currentSpeedMbps >= 35.0 || (preferMax && currentSpeedMbps >= 25.0) {
                return "2160"
            }
        }
        
        // 2. Check for 2K (1440p)
        if sorted.contains(where: { $0 >= 1440 }) {
            if currentSpeedMbps >= 18.0 || (preferMax && currentSpeedMbps >= 14.0) {
                return "1440"
            }
        }
        
        // 3. Check for 1080p (Full HD) - Pristine quality and instant streaming
        if sorted.contains(where: { $0 >= 1080 }) {
            return "1080"
        }
        
        // 4. Check for 720p (HD)
        if sorted.contains(where: { $0 >= 720 }) {
            return "720"
        }
        
        // 5. Fallback to highest available resolution in the list
        if let highest = sorted.first {
            return "\(highest)"
        }
        
        return "1080"
    }
    
    // MARK: - Formatting Helpers
    public var displaySpeed: String {
        if currentSpeedMbps >= 100 {
            return String(format: "%.0f Mbps", currentSpeedMbps)
        } else {
            return String(format: "%.1f Mbps", currentSpeedMbps)
        }
    }
    
    public var displayLatency: String {
        return String(format: "%.0f ms", latencyMs)
    }
    
    public var statusSummary: String {
        switch networkTier {
        case .ultra:
            return "Rất mạnh • Đủ chuẩn 4K Ultra HD"
        case .veryHigh:
            return "Mạnh • Đủ chuẩn 2K Quad HD"
        case .high:
            return "Ổn định • Đủ chuẩn 1080p Full HD"
        case .medium:
            return "Khá • Đủ chuẩn 720p HD"
        case .low:
            return "Yếu • Tiết kiệm dữ liệu (SD)"
        }
    }
}
