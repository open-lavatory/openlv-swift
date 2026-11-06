import Foundation

/// Serializes cancellation with handle disposal. The generated async runtime
/// clears the handle before freeing it, so late cancellation cannot use freed memory.
final class RustFutureCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: UInt64?
    private let cancelFunction: (@Sendable (UInt64) -> Void)?

    init(handle: UInt64, cancel: (@Sendable (UInt64) -> Void)?) {
        self.handle = handle
        self.cancelFunction = cancel
    }

    func cancel() {
        lock.withLock {
            if let handle { cancelFunction?(handle) }
        }
    }

    func finish() {
        lock.withLock { handle = nil }
    }
}
