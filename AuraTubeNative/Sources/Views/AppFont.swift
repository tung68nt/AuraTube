import Foundation
import CoreText
import AppKit
import SwiftUI

public enum AppFont {
    private static var isRegistered = false
    
    /// Register bundled custom fonts into CoreText process memory
    public static func registerCustomFonts() {
        guard !isRegistered else { return }
        isRegistered = true
        
        var searchURLs: [URL] = []
        
        // 1. App Bundle Resources
        if let resURL = Bundle.main.resourceURL {
            searchURLs.append(resURL.appendingPathComponent("Fonts"))
            searchURLs.append(resURL)
        }
        
        // 2. Development / Workspace fallback
        let devPath = "/Users/tungnguyen/Code/Youtube/AuraTubeNative/Resources/Fonts"
        searchURLs.append(URL(fileURLWithPath: devPath))
        
        let fileManager = FileManager.default
        var loadedCount = 0
        
        for folderURL in searchURLs {
            guard fileManager.fileExists(atPath: folderURL.path) else { continue }
            if let files = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                for fileURL in files {
                    let ext = fileURL.pathExtension.lowercased()
                    if ext == "ttf" || ext == "otf" {
                        var err: Unmanaged<CFError>?
                        if CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &err) {
                            loadedCount += 1
                        }
                    }
                }
            }
            if loadedCount > 0 { break }
        }
    }
    
    /// Official YouTube Sans font with graceful fallback to system font
    public static func youTubeSans(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        registerCustomFonts()
        
        let fontName: String
        switch weight {
        case .black, .heavy:
            fontName = "YouTubeSans-ExtraBold"
        case .bold:
            fontName = "YouTubeSans-Bold"
        case .semibold:
            fontName = "YouTubeSans-SemiBold"
        case .medium:
            fontName = "YouTubeSans-Medium"
        default:
            fontName = "YouTubeSans-Bold"
        }
        
        if NSFont(name: fontName, size: size) != nil {
            return .custom(fontName, size: size)
        } else {
            return .system(size: size, weight: weight)
        }
    }
}
