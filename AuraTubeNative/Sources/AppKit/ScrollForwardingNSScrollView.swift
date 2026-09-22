import SwiftUI
import AppKit
import ObjectiveC

/// Custom NSScrollView subclass that forwards dominant vertical scroll gestures
/// up to the parent enclosing vertical scroll view instead of swallowing them.
public final class ForwardingHorizontalNSScrollView: NSScrollView {
    public override func scrollWheel(with event: NSEvent) {
        let deltaY = abs(event.scrollingDeltaY)
        let deltaX = abs(event.scrollingDeltaX)
        
        // If dominant gesture is vertical (standard mouse wheel or vertical swipe)
        if deltaY > deltaX || (deltaX < 0.01 && deltaY > 0.01) {
            if let parent = self.superview?.enclosingScrollView {
                parent.scrollWheel(with: event)
                return
            }
        }
        super.scrollWheel(with: event)
    }
}

/// Invisible helper NSView that identifies its enclosing horizontal NSScrollView
/// and dynamically upgrades its class to ForwardingHorizontalNSScrollView.
public final class ScrollForwardingHelperView: NSView {
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        upgradeEnclosingScrollView()
    }
    
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        upgradeEnclosingScrollView()
    }
    
    private func upgradeEnclosingScrollView() {
        guard let scrollView = self.enclosingScrollView,
              !(scrollView is ForwardingHorizontalNSScrollView) else { return }
        object_setClass(scrollView, ForwardingHorizontalNSScrollView.self)
    }
}

public struct ScrollForwardingRepresentable: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> ScrollForwardingHelperView {
        ScrollForwardingHelperView()
    }
    
    public func updateNSView(_ nsView: ScrollForwardingHelperView, context: Context) {}
}

extension View {
    /// Forwards vertical scroll wheel gestures on horizontal ScrollViews to the enclosing vertical ScrollView,
    /// completely eliminating the "dead zone" / "mouse disconnected" trap when scrolling over horizontal rows.
    public func forwardVerticalScroll() -> some View {
        self.background(ScrollForwardingRepresentable())
    }
}
