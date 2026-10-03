import AppKit

/// Global scroll-speed amplifier for every SwiftUI/AppKit scroll view in the app.
/// macOS default scroll distance is tuned for small documents; long video grids feel slow.
/// Multiplies trackpad (precise) and mouse-wheel deltas. Momentum events are scaled too,
/// so inertia stays natural. Idempotent via an event tag (safe if several monitors see the event).
@MainActor
public enum ScrollBoost {
    public static let speedKey = "auratube_scroll_speed"
    /// Set true by views that implement their own wheel handling (Shorts feed).
    public static var suspended = false
    
    private static var monitor: Any?
    private static let tag: Int64 = 0x41555241 // "AURA"
    
    /// User-adjustable multiplier. 1.0 = system default.
    public static var userMultiplier: Double {
        let v = UserDefaults.standard.double(forKey: speedKey)
        return v > 0 ? min(max(v, 0.5), 5.0) : 1.0
    }
    
    public static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            return boosted(event)
        }
    }
    
    public static func boosted(_ event: NSEvent) -> NSEvent {
        guard !suspended, let cg = event.cgEvent else { return event }
        if cg.getIntegerValueField(.eventSourceUserData) == tag { return event }
        if let w = event.window, PiPWindowController.shared.isPipWindow(w) { return event }
        
        // Base boost: trackpad needs less than a notched wheel.
        let base: Double = event.hasPreciseScrollingDeltas ? 2.2 : 3.5
        let factor = base * userMultiplier
        
        guard let copy = cg.copy() else { return event }
        
        for axis in [
            (CGEventField.scrollWheelEventFixedPtDeltaAxis1, CGEventField.scrollWheelEventPointDeltaAxis1, CGEventField.scrollWheelEventDeltaAxis1),
            (CGEventField.scrollWheelEventFixedPtDeltaAxis2, CGEventField.scrollWheelEventPointDeltaAxis2, CGEventField.scrollWheelEventDeltaAxis2)
        ] {
            let fixed = copy.getDoubleValueField(axis.0) * factor
            copy.setDoubleValueField(axis.0, value: fixed)
            let point = Double(copy.getIntegerValueField(axis.1)) * factor
            copy.setIntegerValueField(axis.1, value: Int64(point.rounded()))
            let line = Double(copy.getIntegerValueField(axis.2)) * factor
            // Keep at least 1 line so slow wheel ticks never round to zero
            let rounded = Int64(line.rounded())
            copy.setIntegerValueField(axis.2, value: rounded == 0 && line != 0 ? (line > 0 ? 1 : -1) : rounded)
        }
        copy.setIntegerValueField(.eventSourceUserData, value: tag)
        return NSEvent(cgEvent: copy) ?? event
    }
}
