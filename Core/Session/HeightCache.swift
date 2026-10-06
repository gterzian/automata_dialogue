import Foundation

/// Never remeasure content on every layout pass. Cache a height keyed by
/// content + width, invalidate only on genuine change. The coordinator drops
/// rows evicted from the materialized window.
///
/// Rows whose content changes (a streaming row) carry a content `tag`; a nil
/// tag only ever hits a nil-tag entry, so a stale height is never reused. Pure
/// data: the measure closure is supplied by the caller.
///
/// Thread safety: the coordinator mutates on the main thread, but the class is
/// lock-guarded and `@unchecked Sendable` so an off-main pre-measurer can hold
/// it across a task boundary. The measure closure runs outside the lock.
public final class HeightCache: @unchecked Sendable {
    private struct Entry {
        var width: CGFloat
        var height: CGFloat
        var tag: String?
    }

    private var cache: [String: Entry] = [:]
    private let lock = NSLock()

    public init() {}

    public func height(for id: String, width: CGFloat, tag: String? = nil, measure: () -> CGFloat) -> CGFloat {
        lock.lock()
        if let cached = cache[id], abs(cached.width - width) < 0.5, cached.tag == tag {
            let height = cached.height
            lock.unlock()
            return height
        }
        lock.unlock()
        let height = measure()
        lock.lock()
        cache[id] = Entry(width: width, height: height, tag: tag)
        lock.unlock()
        return height
    }

    public func heightIfPresent(for id: String, width: CGFloat) -> CGFloat? {
        lock.withLock {
            guard let cached = cache[id], abs(cached.width - width) < 0.5 else { return nil }
            return cached.height
        }
    }

    public func cached(for id: String, width: CGFloat) -> (height: CGFloat, tag: String?)? {
        lock.withLock {
            guard let cached = cache[id], abs(cached.width - width) < 0.5 else { return nil }
            return (cached.height, cached.tag)
        }
    }

    public func invalidate(_ id: String) {
        lock.withLock { cache.removeValue(forKey: id) }
    }

    public func clear() {
        lock.withLock { cache.removeAll() }
    }

    public func store(_ id: String, width: CGFloat, height: CGFloat, tag: String? = nil) {
        lock.withLock { cache[id] = Entry(width: width, height: height, tag: tag) }
    }

    public var count: Int {
        lock.withLock { cache.count }
    }
}
