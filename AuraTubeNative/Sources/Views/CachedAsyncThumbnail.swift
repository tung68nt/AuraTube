import SwiftUI
import AppKit

/// Butter-smooth cached image view that prioritizes RAM cache for 120Hz scrolling
/// and decodes off-main-thread without blocking the UI runloop.
public struct CachedAsyncThumbnail<Content: View, Placeholder: View>: View {
    let url: String
    let maxPixelSize: CGFloat
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var loadedImage: NSImage?
    @State private var loadTask: Task<Void, Never>?
    
    public init(
        url: String,
        maxPixelSize: CGFloat = 640,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.content = content
        self.placeholder = placeholder
        
        // Fast synchronous RAM cache initialization on first render
        _loadedImage = State(initialValue: AuraImageCache.shared.imageFromMemory(for: url))
    }
    
    public var body: some View {
        Group {
            if let image = loadedImage {
                content(Image(nsImage: image))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: url) { newUrl in
            loadedImage = AuraImageCache.shared.imageFromMemory(for: newUrl)
            loadImageIfNeeded()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private func loadImageIfNeeded() {
        guard !url.isEmpty else { return }
        if let memoryHit = AuraImageCache.shared.imageFromMemory(for: url) {
            self.loadedImage = memoryHit
            return
        }
        
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            let img = await AuraImageCache.shared.loadImage(for: url, maxPixelSize: maxPixelSize)
            if !Task.isCancelled {
                self.loadedImage = img
            }
        }
    }
}

// Convenience initializer for simple contentMode + placeholderColor
extension CachedAsyncThumbnail where Content == AnyView, Placeholder == Color {
    public init(
        url: String,
        maxPixelSize: CGFloat = 640,
        contentMode: ContentMode = .fill,
        placeholderColor: Color = Color(white: 0.14)
    ) {
        self.init(
            url: url,
            maxPixelSize: maxPixelSize,
            content: { image in
                AnyView(image.resizable().aspectRatio(contentMode: contentMode))
            },
            placeholder: {
                placeholderColor
            }
        )
    }
}
