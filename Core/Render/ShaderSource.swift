import Foundation

/// Metal Shading Language sources, compiled at startup from strings with the
/// Metal 4 compiler. SwiftPM cannot build a `.metallib`, so the source lives in
/// strings. `simulation` seeds the board and advances it; `layer` compacts the
/// fitted grid into spans and draws them through a GPU-built indirect draw (see
/// `LayerRenderer`).
public enum ShaderSource {
    public static let simulation = """
    #include <metal_stdlib>
    using namespace metal;

    struct StepParams {
        uint width;
        uint rule;    // elementary rule bits, or totalistic code
        uint colors;  // 0 selects the elementary kernel
        uint capacity; // history rows; the source step is taken modulo this
        uint inject;   // 1 = overwrite the centre cell after each step
        ulong injectSeed; // base of the per-step injection draw
    };

    // The injected-randomness draw: the SplitMix64 mix of `seed + step × golden`,
    // indexed by step so no thread carries the generator's state.
    static ulong injection_value(ulong seed, ulong step) {
        ulong z = seed + step * 0x9E3779B97F4A7C15UL;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        return z ^ (z >> 31);
    }

    struct ViewParams {
        uint boardWidth;
        uint displayCols;
        uint displayRows;
        uint capacity;       // history rows, modulo index
        uint viewportStart;  // newest window's top source step
        uint viewportOrigin; // first source column the window shows
        uint currentStep;    // source rows computed so far
    };

    // The seed row. `mode` selects the `BoardStart` shape: 0 center cell,
    // 1 rightmost cell, 2 random row, 3 random 2-cell blocks, 4 repeated
    // block, 5 base-`colors` number written from the center.
    struct SeedParams {
        uint width;
        uint colors;
        uint mode;
        uint blockLength;
        uint number;
        float density;
        ulong seed;
    };

    // The row being computed is read from a GPU-side head counter that
    // `bump_head` advances, so every dispatch in the run binds the same
    // buffers. The argument table is live at GPU
    // execution time, so per-dispatch address updates would all resolve to the
    // last value.
    kernel void step_eca(device uchar* history [[buffer(0)]],
                         constant StepParams& p [[buffer(1)]],
                         device const uint* head [[buffer(2)]],
                         uint gid [[thread_position_in_grid]]) {
        if (gid >= p.width) return;
        uint readRow = *head;
        uint writeRow = readRow + 1;
        uint i = gid;
        uint base = (readRow % p.capacity) * p.width;
        uint writeBase = (writeRow % p.capacity) * p.width;
        uint l = history[base + (i + p.width - 1) % p.width];
        uint c = history[base + i];
        uint r = history[base + (i + 1) % p.width];
        uint neighborhood = (l << 2) | (c << 1) | r;
        history[writeBase + i] = uchar((p.rule >> neighborhood) & 1u);
        if (p.inject != 0 && i == p.width / 2) {
            ulong draw = injection_value(p.injectSeed, ulong(readRow + 1));
            history[writeBase + i] = uchar(draw % 2);
        }
    }

    kernel void step_totalistic(device uchar* history [[buffer(0)]],
                                constant StepParams& p [[buffer(1)]],
                                device const uint* head [[buffer(2)]],
                                uint gid [[thread_position_in_grid]]) {
        if (gid >= p.width) return;
        uint readRow = *head;
        uint writeRow = readRow + 1;
        uint i = gid;
        uint base = (readRow % p.capacity) * p.width;
        uint writeBase = (writeRow % p.capacity) * p.width;
        uint l = history[base + (i + p.width - 1) % p.width];
        uint c = history[base + i];
        uint r = history[base + (i + 1) % p.width];
        uint sum = l + c + r;
        uint divisor = 1;
        for (uint k = 0; k < sum; ++k) { divisor *= p.colors; }
        history[writeBase + i] = uchar((p.rule / divisor) % p.colors);
        if (p.inject != 0 && i == p.width / 2) {
            ulong draw = injection_value(p.injectSeed, ulong(readRow + 1));
            history[writeBase + i] = uchar(draw % p.colors);
        }
    }

    kernel void step_k2r2(device uchar* history [[buffer(0)]],
                          constant StepParams& p [[buffer(1)]],
                          device const uint* head [[buffer(2)]],
                          uint gid [[thread_position_in_grid]]) {
        if (gid >= p.width) return;
        uint readRow = *head;
        uint writeRow = readRow + 1;
        uint i = gid;
        uint base = (readRow % p.capacity) * p.width;
        uint writeBase = (writeRow % p.capacity) * p.width;
        uint sum = history[base + (i + p.width - 2) % p.width]
                 + history[base + (i + p.width - 1) % p.width]
                 + history[base + i]
                 + history[base + (i + 1) % p.width]
                 + history[base + (i + 2) % p.width];
        history[writeBase + i] = uchar((p.rule >> sum) & 1u);
        if (p.inject != 0 && i == p.width / 2) {
            ulong draw = injection_value(p.injectSeed, ulong(readRow + 1));
            history[writeBase + i] = uchar(draw % 2);
        }
    }

    kernel void bump_head(device uint* head [[buffer(0)]],
                          uint gid [[thread_position_in_grid]]) {
        if (gid == 0) { *head = *head + 1; }
    }

    // The `index`-th (1-based) SplitMix64 draw, so a random seed row can be
    // built per cell without carrying the generator's state between threads.
    static ulong seed_value(ulong seed, uint index) {
        return injection_value(seed, ulong(index));
    }

    static uint digit_count(uint number, uint colors) {
        uint count = 1;
        uint n = number;
        while (n >= colors) { n /= colors; count += 1; }
        return count;
    }

    // `index` 0 is the most significant base-`colors` digit.
    static uchar number_digit(uint number, uint colors, uint index, uint count) {
        uint power = 1;
        for (uint k = 0; k < count - 1 - index; ++k) { power *= colors; }
        return uchar((number / power) % colors);
    }

    kernel void seed_row(device uchar* history [[buffer(0)]],
                         constant SeedParams& p [[buffer(1)]],
                         device const uchar* block [[buffer(2)]],
                         uint gid [[thread_position_in_grid]]) {
        if (gid >= p.width) return;
        uchar value = 0;
        if (p.mode == 0) {
            value = (gid == p.width / 2) ? 1 : 0;
        } else if (p.mode == 1) {
            value = (gid == p.width - 1) ? 1 : 0;
        } else if (p.mode == 2) {
            ulong draw = seed_value(p.seed, gid + 1);
            if (p.colors == 3) {
                value = uchar(draw % 3);
            } else if (p.density == 0.5f) {
                value = uchar(draw & 1);
            } else {
                value = ((draw >> 11) * (1.0 / 9007199254740992.0) < p.density) ? 1 : 0;
            }
        } else if (p.mode == 3) {
            value = uchar(seed_value(p.seed, gid / 2 + 1) & 1);
        } else if (p.mode == 4) {
            if (p.blockLength > 0) { value = block[gid % p.blockLength]; }
        } else {
            uint origin = p.width / 2;
            uint count = digit_count(p.number, p.colors);
            if (gid >= origin && gid - origin < count) {
                value = number_digit(p.number, p.colors, gid - origin, count);
            }
        }
        history[gid] = value;
    }

    // The window shows one board cell per display column at `viewportOrigin`.
    // Rows the run has not reached yet stay background, so a short board grows
    // from the top before it starts to scroll.
    kernel void fit(device const uchar* history [[buffer(0)]],
                    device uchar* colorGrid [[buffer(1)]],
                    constant ViewParams& p [[buffer(2)]],
                    uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.displayCols || gid.y >= p.displayRows) return;
        uint target = p.viewportStart + gid.y;
        uint index = p.viewportOrigin + gid.x;
        uchar value = 0;
        if (target <= p.currentStep && index < p.boardWidth) {
            value = history[(target % p.capacity) * p.boardWidth + index];
        }
        colorGrid[gid.y * p.displayCols + gid.x] = value;
    }
    """

    public static let layer = """
    #include <metal_stdlib>
    using namespace metal;

    // One horizontal run of same-colour, non-background cells (draw cost
    // follows the structure). Layout mirrors `LayerRenderer.Span`.
    struct Span {
        uint row;
        uint start;
        uint length;
        uint color;
    };

    struct LayerUniforms {
        uint cols;
        uint rows;
        uint padding0;
        uint padding1;
    };

    // Matches MTLDrawPrimitivesIndirectArguments; `encode_draw` fills it in.
    struct DrawArguments {
        uint vertexCount;
        uint instanceCount;
        uint vertexStart;
        uint baseInstance;
    };

    kernel void clear_counter(device atomic_uint* counter [[buffer(0)]],
                              uint gid [[thread_position_in_grid]]) {
        if (gid == 0) { atomic_store_explicit(counter, 0, memory_order_relaxed); }
    }

    kernel void runs(device const uchar* cells [[buffer(0)]],
                     device Span* spans [[buffer(1)]],
                     device atomic_uint* counter [[buffer(2)]],
                     constant LayerUniforms& u [[buffer(3)]],
                     uint2 gid [[thread_position_in_grid]]) {
        uint col = gid.x;
        uint row = gid.y;
        if (col >= u.cols || row >= u.rows) return;
        uint index = row * u.cols + col;
        uchar value = cells[index];
        if (value == 0) return;
        // A run starts where the left neighbour is background or a different
        // colour; only that cell writes, so no two threads claim one span.
        if (col != 0 && cells[index - 1] == value) return;
        uint length = 1;
        while (col + length < u.cols && cells[index + length] == value) { length += 1; }
        uint slot = atomic_fetch_add_explicit(counter, 1, memory_order_relaxed);
        spans[slot] = Span{row, col, length, uint(value)};
    }

    kernel void encode_draw(device const uint* counter [[buffer(0)]],
                            device DrawArguments* arguments [[buffer(1)]],
                            uint gid [[thread_position_in_grid]]) {
        if (gid != 0) return;
        arguments->vertexCount = 6;
        arguments->instanceCount = *counter;
        arguments->vertexStart = 0;
        arguments->baseInstance = 0;
    }

    struct LayerVertexOut {
        float4 position [[position]];
        float4 color;
    };

    // One instance per span; six vertices form the quad. Row 0 is the top edge.
    vertex LayerVertexOut layer_vertex(uint vid [[vertex_id]],
                                       uint iid [[instance_id]],
                                       const device Span* spans [[buffer(0)]],
                                       constant LayerUniforms& u [[buffer(1)]],
                                       constant float4* palette [[buffer(2)]]) {
        Span s = spans[iid];
        float2 corner = float2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0,
                               (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);
        float x = (float(s.start) + corner.x * float(s.length)) / float(u.cols);
        float y = (float(s.row) + corner.y) / float(u.rows);
        LayerVertexOut out;
        out.position = float4(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
        out.color = palette[s.color];
        return out;
    }

    fragment float4 layer_fragment(LayerVertexOut in [[stage_in]]) {
        return in.color;
    }
    """

    /// The "working" indicator the review window shows while the model runs:
    /// expanding rings over the background, time-driven in the fragment shader
    /// so no per-frame geometry is built on the CPU.
    public static let indicator = """
    #include <metal_stdlib>
    using namespace metal;

    struct IndicatorUniforms {
        float time;      // seconds since the animation started
        float aspect;    // drawable width / height
        float thickness; // gaussian band width in radius units
        float padding;
        float4 background;
        float4 ink;
    };

    struct IndicatorVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    // A single oversized triangle covers the drawable; the fragment paints the
    // rings from the interpolated coordinate.
    vertex IndicatorVertexOut indicator_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        float2 position = positions[vid];
        IndicatorVertexOut out;
        out.position = float4(position, 0.0, 1.0);
        out.uv = position * 0.5 + 0.5;
        return out;
    }

    fragment float4 indicator_fragment(IndicatorVertexOut in [[stage_in]],
                                       constant IndicatorUniforms& u [[buffer(0)]]) {
        // Seconds per full expansion. Long and calm, so the rings read as slow
        // water rather than a metronome.
        const float RING_SECONDS = 5.0;

        float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
        // 0 at the centre, 1 at the top/bottom edge, so rings stay circular.
        float radius = length(p) * 2.0;
        // A slow angular wobble keeps a ring off a perfect circle, the way a
        // ripple distorts as it crosses moving water.
        float angle = atan2(p.y, p.x);
        radius += 0.02 * sin(angle * 5.0 + u.time * 0.6);
        float alpha = 0.0;
        for (int i = 0; i < 6; ++i) {
            // Each ring is offset a sixth of the cycle. It grows out to the edge
            // and pulls back in, so the whole thing beats like a heart rather
            // than only expanding.
            float phase = fract(u.time / RING_SECONDS + float(i) / 6.0);
            float grow = phase < 0.5 ? phase * 2.0 : (1.0 - phase) * 2.0;
            float d = radius - grow;
            // A wide gaussian band instead of a hard edge: soft and diffuse.
            float band = exp(-(d * d) / (u.thickness * u.thickness));
            // Brightest at full expansion, dark at the centre, like a pulse.
            float pulse = sin(phase * 3.14159265);
            // A faint travelling shimmer, like light across disturbed water.
            float shimmer = 0.82 + 0.18 * sin(radius * 22.0 - u.time * 1.4);
            alpha += band * pulse * shimmer;
        }
        alpha = clamp(alpha, 0.0, 1.0);
        return mix(u.background, u.ink, alpha);
    }
    """
}
