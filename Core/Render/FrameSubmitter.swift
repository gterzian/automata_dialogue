import Foundation
import Metal

/// A reusable per-frame command allocator and command buffer. `FrameSlotRing`
/// rotates three of them so frame N+1/N+2 could be encoded while the GPU runs
/// N. Every commit waits for the GPU today, so the rotation is structural until
/// that wait is dropped (see `README.md`).
@available(macOS 26.0, *)
final class FrameSlot: @unchecked Sendable {
    let allocator: any MTL4CommandAllocator
    let command: any MTL4CommandBuffer
    private let available = DispatchSemaphore(value: 1)

    init(device: any MTLDevice, label: String) throws {
        guard let allocator = device.makeCommandAllocator(),
              let command = device.makeCommandBuffer() else {
            throw GPUContext.GPUError.resource("frame slot \(label)")
        }
        self.allocator = allocator
        self.command = command
    }

    /// Waits until the slot's previous frame has finished on the GPU.
    func acquire() { available.wait() }

    /// Returns the slot to the ring. Called when the GPU finishes the frame.
    func release() { available.signal() }
}

@available(macOS 26.0, *)
final class FrameSlotRing {
    private let slots: [FrameSlot]
    private var next = 0

    init(device: any MTLDevice, count: Int = 3) throws {
        var slots: [FrameSlot] = []
        for index in 0..<max(1, count) {
            slots.append(try FrameSlot(device: device, label: "\(index)"))
        }
        self.slots = slots
    }

    func borrow() -> (index: Int, slot: FrameSlot) {
        let index = next
        let slot = slots[index]
        next = (next + 1) % slots.count
        slot.acquire()
        return (index, slot)
    }
}

/// Encodes one frame's commands and commits them. The slot ring, the residency
/// set, the completion handler, and the wait are the same for the simulation's
/// compute pass and for every renderer's render pass, so they live here and a
/// caller only encodes.
@available(macOS 26.0, *)
struct FrameSubmitter {
    private let context: GPUContext
    private let ring: FrameSlotRing

    init(context: GPUContext) throws {
        self.context = context
        self.ring = try FrameSlotRing(device: context.device)
    }

    /// Commits the frame and blocks until the GPU finishes it, so the caller may
    /// rewrite the shared buffers and uniforms the frame read, and so a caller
    /// holding the surface may read it back. A pipeline that did not wait would
    /// need a per-slot copy of each shared buffer.
    func submit(_ encode: (any MTL4CommandBuffer) throws -> Void) throws {
        let (_, slot) = ring.borrow()
        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)
        do {
            try encode(slot.command)
            slot.command.endCommandBuffer()
        } catch {
            // Nothing was committed, so the allocator has no work in flight and
            // the slot can return to the ring for the next frame.
            slot.allocator.reset()
            slot.release()
            throw error
        }

        let done = DispatchSemaphore(value: 0)
        let options = MTL4CommitOptions()
        options.addFeedbackHandler { _ in
            slot.allocator.reset()
            slot.release()
            done.signal()
        }
        context.queue.commit([slot.command], options: options)
        done.wait()
    }
}
