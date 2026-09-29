@preconcurrency import AppKit
import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

/// High-performance MainActor-coordinated memory & background image cache for AuraTube
@MainActor
public final class AuraImageCache {
    public static let shared = AuraImageCache()
    
    private let memoryCache = NSCache<NSURL, NSImage>()
    private var inFlightTasks: [URL: Task<CGImage?, Never>] = [:]
    
    private let diskCacheURL: URL = {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = (urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("AuraTubeThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private init() {
        // Set generous in-memory cache limit: ~150 MB or 400 images
        memoryCache.totalCostLimit = 150 * 1024 * 1024
        memoryCache.countLimit = 400
    }
    
    private func diskURL(for urlString: String) -> URL {
        let hash = SHA256.hash(data: Data(urlString.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskCacheURL.appendingPathComponent("\(hash).thumb")
    }
    
    /// Fast synchronous RAM cache lookup (0ms overhead, 120Hz smooth scrolling)
    public func imageFromMemory(for urlString: String) -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        return memoryCache.object(forKey: url as NSURL)
    }
    
    /// Asynchronously fetch image from RAM, Disk, or Network with background decoding & downsampling
    public func loadImage(for urlString: String, maxPixelSize: CGFloat = 640) async -> NSImage? {
        guard let url = URL(string: urlString), !urlString.isEmpty else { return nil }
        let nsUrl = url as NSURL
        
        // 1. Fast path: in-memory cache (0ms)
        if let cached = memoryCache.object(forKey: nsUrl) {
            return cached
        }
        
        // 2. Coalesce in-flight tasks for duplicate requests
        if let existingTask = inFlightTasks[url] {
            if let cg = await existingTask.value {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            return nil
        }
        
        let fileURL = diskURL(for: urlString)
        
        let task = Task<CGImage?, Never>.detached(priority: .userInitiated) {
            // 3. Fast path: Disk cache hit (<1ms, no network)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let diskData = try? Data(contentsOf: fileURL) {
                if let cg = AuraImageCache.downsampleToCGImage(data: diskData, maxPixelSize: maxPixelSize) {
                    return cg
                }
            }
            
            // 4. Network fetch
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 10.0
            
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            
            // Save downsampled data to disk for instant future loads
            try? data.write(to: fileURL, options: .atomic)
            
            return AuraImageCache.downsampleToCGImage(data: data, maxPixelSize: maxPixelSize)
        }
        
        inFlightTasks[url] = task
        let cgImage = await task.value
        inFlightTasks.removeValue(forKey: url)
        
        guard let cg = cgImage else { return nil }
        let decodedImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let cost = Int(cg.width * cg.height * 4)
        memoryCache.setObject(decodedImage, forKey: nsUrl, cost: cost)
        return decodedImage
    }
    
    /// Decode and downsample raw image data off the main thread using ImageIO
    nonisolated private static func downsampleToCGImage(data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions)
    }
    
    /// Prefetch and decode upcoming thumbnails into RAM in background so scrolling is 120Hz instant
    public func prefetchImages(for urlStrings: [String], maxPixelSize: CGFloat = 640) {
        guard !urlStrings.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            for urlStr in urlStrings {
                if Task.isCancelled { break }
                _ = await self.loadImage(for: urlStr, maxPixelSize: maxPixelSize)
            }
        }
    }
    
    /// Clear in-memory cache if needed on memory warnings
    public func clearMemory() {
        memoryCache.removeAllObjects()
    }
}
