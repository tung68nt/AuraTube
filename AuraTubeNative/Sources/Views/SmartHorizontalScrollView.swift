import SwiftUI
import AppKit

// MARK: - Smart Horizontal ScrollView (Zero Nested Scroll Trap)
/// A custom SwiftUI ScrollView wrapper for horizontal scrolling on macOS.
/// Solves the classic AppKit "Nested Scroll Trap" issue where hovering over a horizontal
/// scroll view intercepts and swallows vertical trackpad/mouse scroll wheel events,
/// causing the outer vertical page scroll to freeze/lock up.
///
/// Features:
/// 1. Gesture Phase Locking: Accurately distinguishes between intentional horizontal swipes and vertical page scrolling.
/// 2. Seamless Vertical Pass-Through: Forwards vertical scrolling (dy > dx) to the enclosing parent vertical NSScrollView in real time.
/// 3. Zero-Swizzling Safety: Uses official AppKit local event monitoring scoped exclusively to the view's window bounds.
public struct SmartHorizontalScrollView<Content: View>: View {
    private let showsIndicators: Bool
    private let content: Content
    
    public init(showsIndicators: Bool = false, @ViewBuilder content: () -> Content) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: showsIndicators) {
            content
        }
        .background(SmartScrollTrackingRepresentable())
    }
}

// MARK: - AppKit Tracking Representable
private struct SmartScrollTrackingRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> SmartScrollTrackingView {
        SmartScrollTrackingView()
    }
    
    func updateNSView(_ nsView: SmartScrollTrackingView, context: Context) {}
}

// MARK: - Smart Scroll Tracking NSView
private final class SmartScrollTrackingView: NSView {
    private var eventMonitor: Any?
    private var activeDirection: ScrollDirection = .none
    
    private enum ScrollDirection {
        case none
        case vertical
        case horizontal
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupMonitor()
        } else {
            removeMonitor()
        }
    }
    
    deinit {
        removeMonitor()
    }
    
    private func setupMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            return self.handleScrollWheel(event)
        }
    }
    
    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        activeDirection = .none
    }
    
    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard let window = self.window, window == event.window else {
            return event
        }
        
        // Exact live coordinate translation in window space
        let boundsInWindow = self.convert(self.bounds, to: nil)
        guard boundsInWindow.contains(event.locationInWindow) else {
            // Mouse is not over this horizontal shelf, let event pass normally
            return event
        }
        
        let dx = abs(event.scrollingDeltaX)
        let dy = abs(event.scrollingDeltaY)
        
        // 1. Trackpad gesture phase tracking (avoids axis jitter midway through a gesture)
        switch event.phase {
        case .began:
            activeDirection = (dy > dx) ? .vertical : .horizontal
            
        case .changed:
            if activeDirection == .none && (dx > 0.4 || dy > 0.4) {
                activeDirection = (dy > dx) ? .vertical : .horizontal
            }
            
        case .ended, .cancelled:
            let finishedDirection = activeDirection
            activeDirection = .none
            if finishedDirection == .vertical {
                forwardToOuterScrollView(event)
                return nil
            } else {
                return event
            }
            
        default:
            // Momentum phase (coasting after finger release)
            if event.momentumPhase != [] {
                if activeDirection == .vertical {
                    forwardToOuterScrollView(event)
                    return nil
                } else if activeDirection == .horizontal {
                    return event
                }
            }
            
            // Traditional mouse wheel with no phase data (e.g. Logitech wheel)
            if event.phase == [] && event.momentumPhase == [] {
                if dy > dx {
                    forwardToOuterScrollView(event)
                    return nil
                } else {
                    return event
                }
            }
        }
        
        // If locked to vertical, forward event to parent scrollview and consume it
        // so the inner horizontal NSScrollView never swallows it or freezes the page
        if activeDirection == .vertical {
            forwardToOuterScrollView(event)
            return nil
        }
        
        // Genuine horizontal scroll - let AppKit dispatch to the inner horizontal scrollview
        return event
    }
    
    private func forwardToOuterScrollView(_ event: NSEvent) {
        guard let outer = findOuterVerticalScrollView() else { return }
        outer.scrollWheel(with: event)
    }
    
    private func findOuterVerticalScrollView() -> NSScrollView? {
        var current: NSView? = self.superview
        while let v = current {
            if let sv = v as? NSScrollView {
                // If it's capable of vertical scrolling or is an enclosing scrollview
                if sv.hasVerticalScroller || (sv.documentView?.bounds.height ?? 0) > sv.bounds.height + 10 {
                    return sv
                }
                if let parentSv = sv.enclosingScrollView {
                    return parentSv
                }
            }
            current = v.superview
        }
        return self.enclosingScrollView
    }
}
