import SwiftUI

/// Macro-free drop-in replacement for SwiftUI `@State` that works seamlessly in
/// Command Line Tools (CLT) and SPM without requiring Xcode's proprietary `SwiftUIMacros` plugin.
@propertyWrapper
public struct LocalState<Value>: DynamicProperty {
    @StateObject private var storage: Storage
    
    private final class Storage: ObservableObject {
        @Published var value: Value
        init(_ value: Value) {
            self.value = value
        }
    }
    
    public init(wrappedValue: Value) {
        _storage = StateObject(wrappedValue: Storage(wrappedValue))
    }
    
    public init(initialValue: Value) {
        _storage = StateObject(wrappedValue: Storage(initialValue))
    }
    
    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }
    
    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.storage.value },
            set: { self.storage.value = $0 }
        )
    }
}
