import Foundation

/// A `SerialExecutor` over a dedicated thread's `CFRunLoop`.
/// Metal objects, drawable acquisition, and `present` are confined here so the
/// main thread only configures the layer and posts commands. The run loop is
/// also where a `CAMetalDisplayLink` schedules its ticks, so a tick and the
/// ensuing encode run on the same thread without a hop.
public final class RenderExecutor: SerialExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [UnownedJob] = []
    private var runLoop: CFRunLoop?
    private var stopped = false
    private let ready = DispatchSemaphore(value: 0)

    public init() {
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "RenderExecutor"
        thread.stackSize = 1 << 20
        thread.start()
        ready.wait()
    }

    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        pending.append(job)
        let runLoop = self.runLoop
        lock.unlock()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            self?.drain()
        }
        CFRunLoopWakeUp(runLoop)
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    /// Stops the run loop once every already-enqueued job has run. Further
    /// enqueues are dropped.
    public func shutdown() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let runLoop = self.runLoop
        lock.unlock()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func run() {
        let current = CFRunLoopGetCurrent()
        lock.lock()
        runLoop = current
        lock.unlock()
        // A run loop with no sources returns immediately from `CFRunLoopRun`,
        // which would kill the render thread before the first job arrives. The
        // empty source keeps it alive; the run loop retains it.
        var context = CFRunLoopSourceContext()
        if let keepAlive = CFRunLoopSourceCreate(nil, 0, &context) {
            CFRunLoopAddSource(current, keepAlive, .defaultMode)
        }
        ready.signal()
        CFRunLoopRun()
    }

    /// Runs each queued job on the render thread. The jobs were enqueued in
    /// order, so a serial actor's isolated state is never touched concurrently.
    private func drain() {
        while true {
            lock.lock()
            if pending.isEmpty {
                lock.unlock()
                return
            }
            let job = pending.removeFirst()
            lock.unlock()
            job.runSynchronously(on: asUnownedSerialExecutor())
        }
    }
}
