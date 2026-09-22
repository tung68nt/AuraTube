@preconcurrency import AppKit
import Foundation
import CoreGraphics
import ImageIO

/// High-performance MainActor-coordinated memory & background image cache for AuraTube
@MainActor
public final class AuraImageCache {
    public static let shared = AuraImageCache()
    
    private let memoryCache = NSCache<NSURL, NSImage>()
    private var inFlightTasks: [URL: Task<CGImage?, Never>] = [:]
    
    private init() {
        // Set generous in-memory cache limit: ~150 MB or 300 images
        memoryCache.totalCostLimit = 150 * 1024 * 1024
        memoryCache.countLimit = 300
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
        
        // 1. Fast path: in-memory cache
        if let cached = memoryCache.object(forKey: nsUrl) {
            return cached
        }
        
        // 2. Coalesce in-flight downloads for duplicate requests
        if let existingTask = inFlightTasks[url] {
            if let cg = await existingTask.value {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            return nil
        }
        
        let task = Task<CGImage?, Never>.detached(priority: .userInitiated) {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 12.0
            
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            
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
    
    /// Clear in-memory cache if needed on memory warnings
    public func clearMemory() {
        memoryCache.removeAllObjects()
    }
}
