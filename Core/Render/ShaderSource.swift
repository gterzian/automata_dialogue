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
        uint viewportStart;  // oldest source step the window still shows
        uint viewportOrigin; // first source column the window shows
        uint currentStep;    // source rows computed so far
        uint topRows;        // twin layout: rows from the horizon to an outer edge
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

    // The window shows one board cell per display cell at `viewportOrigin`.
    // Rows the run has not reached yet stay background, so a short board grows
    // from the top before it starts to scroll. Zoom changes `displayCols` and
    // `displayRows`, not this mapping.
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

    // The reveal's mirrored pair: one shared horizon row at the centre, with
    // the upper branch growing up from it and the lower branch growing down
    // from the same row. `p.topRows` is the distance from the horizon to each
    // outer edge, so display rows above and below the horizon read the same
    // source row. The newest source row is pinned to both outer edges; older
    // rows leave through the horizon. The horizon row is written once.
    kernel void fit_twin(device const uchar* history [[buffer(0)]],
                         device uchar* colorGrid [[buffer(1)]],
                         constant ViewParams& p [[buffer(2)]],
                         uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.displayCols || gid.y >= p.displayRows) return;
        uint halfRows = p.topRows;
        uint local = gid.y <= halfRows ? (halfRows - gid.y) : (gid.y - halfRows);
        uint target = p.viewportStart + local;
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

    /// The intro the review window shows while the model's turn is prepared: a
    /// one-cell ink dot ignites, bursts to cover the frame, holds and flickers,
    /// then collapses into the horizon line the reveal's two branches share.
    /// The resting line can then retract onto the single centred cell an entry
    /// seeds from, so the reveal grows out of the intro's last image.
    ///
    /// Everything is drawn by one full-screen fragment shader: the dot, the
    /// bursting mass, the line, and the grain. No offscreen targets or upsample
    /// are needed; the shader writes the drawable directly.
    public static let collapse = """
    #include <metal_stdlib>
    using namespace metal;

    struct CollapseUniforms {
        float time;
        float aspect;
        float screenHeight;
        float noiseScale;
        float smokeStrength;
        float centerX;
        float centerY;
        float noiseX;
        float noiseY;
        float noiseZ;
        float warmth;
        float grainSeed;
        float dotScale;
        float endAlpha;
        float bloom;
        float collapse;
        float lineHalfThickness;
        float frontEnergy;
        float lineSpring;
        float settle;
        float4 white;
        float4 ink;
    };

    struct FullscreenOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex FullscreenOut collapse_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        FullscreenOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.uv = positions[vid] * 0.5 + 0.5;
        return out;
    }

    static float smokeValue(texture3d<float> noise, float2 p, float t, float scale,
                            float3 origin) {
        constexpr sampler s(filter::linear, address::repeat);
        float a = noise.sample(
            s, float3(p * scale + float2(t * 0.010, t * 0.006) + origin.xy,
                      origin.z + t * 0.020)).r;
        float b = noise.sample(
            s, float3(p * scale * 2.1 - float2(t * 0.014, t * 0.004) + origin.yx,
                      origin.z + 0.41 + t * 0.030)).r;
        return a * 0.65 + b * 0.35;
    }

    // The silhouette's angular lobes, read from the volume by direction from
    // the centre so ink spreads unevenly instead of like a perfect circle.
    static float lobeNoise(texture3d<float> noise, float2 dir, float t, float3 origin) {
        constexpr sampler s(filter::linear, address::repeat);
        float a = noise.sample(s, float3(dir * 0.35 + origin.xy, origin.z + t * 0.05)).r;
        float b = noise.sample(s, float3(dir * 0.90 + origin.yx, origin.z + 0.30 + t * 0.09)).r;
        return (a - 0.5) * 0.75 + (b - 0.5) * 0.25;
    }

    // Per-pixel white noise for the film grain; the seed moves each frame.
    static float grainAt(float2 pixel, float seed) {
        float3 p3 = fract(float3(pixel.xyx) * float3(0.1031, 0.1030, 0.0973));
        p3 += dot(p3, p3.yzx + 33.33 + seed);
        return fract((p3.x + p3.y) * p3.z);
    }

    fragment float4 collapse_fragment(FullscreenOut in [[stage_in]],
                                      constant CollapseUniforms& u [[buffer(0)]],
                                      texture3d<float> noise [[texture(0)]]) {
        float2 hp = (in.uv - 0.5) * float2(u.aspect, 1.0);
        float3 origin = float3(u.noiseX, u.noiseY, u.noiseZ);

        // The dot, the bursting mass, and the line are one shape. `bloom` grows
        // the radius from the one-cell seed at a constant log rate, so the front
        // accelerates; `collapse` then narrows the mass into the horizon row.
        float coverRadius = length(float2(u.aspect, 1.0)) * 0.5 + 0.15;
        float seedRadius =
            max(u.lineHalfThickness, 1.0 / max(u.screenHeight, 1.0)) * u.dotScale;
        float bloomRadius = seedRadius * pow(coverRadius / seedRadius, u.bloom);
        float radius = mix(bloomRadius, u.lineHalfThickness, u.collapse) * u.lineSpring;
        float halfWidth = u.collapse * (u.aspect * 0.5 + 0.05);
        float held = 1.0 - u.collapse;

        // The mass drifts to this run's own place; the line it collapses into
        // has to sit exactly on the horizon row the reveal grows from.
        float2 p = hp - float2(u.centerX, u.centerY) * held;

        // The mass carries the field's mottled texture and an uneven silhouette;
        // the line is flat ink, so nothing is sampled once it has collapsed.
        float smoke = 1.0;
        float lobes = 0.0;
        if (held > 0.0) {
            smoke = mix(
                1.0, 0.75 + 0.5 * smokeValue(noise, p, u.time, u.noiseScale, origin),
                u.smokeStrength);
            float2 dir = p / max(length(p), 1e-4);
            lobes = lobeNoise(noise, dir, u.time, origin);
        }
        float settle = 1.0 - smoothstep(0.55, 1.0, u.collapse);
        float breathing = 1.0 + 0.012 * sin(u.time * 2.1 + u.grainSeed) * held;
        float effRadius = radius * (1.0 + 1.2 * lobes * settle) * breathing;

        // The collapsing pill starts slightly tilted and rights itself.
        float tilt = sin(u.grainSeed) * 0.12 * held;
        float2 hr = float2(p.x * cos(tilt) - p.y * sin(tilt),
                           p.x * sin(tilt) + p.y * cos(tilt));
        float2 q = float2(max(abs(hr.x) - halfWidth, 0.0), hr.y);
        // The finale retracts the line onto the reveal's seed: one cell, half a
        // cell right of the frame's centre, as tall as the horizon row.
        float2 cell = hr - float2(u.lineHalfThickness, 0.0);
        float distance = mix(length(q), max(abs(cell.x), abs(cell.y)), u.settle);

        // Fast fronts carry a wider, softer edge; the settled line is crisp.
        float soft = max(effRadius * 0.5 * (1.0 + 0.9 * u.frontEnergy),
                         1.5 / max(u.screenHeight, 1.0));
        float body = 1.0 - smoothstep(-soft, soft, distance - effRadius);

        // The held mass flickers between near-black and a warm dark brown, with a
        // slightly lighter heart; both fade to the pure ink colour of the line.
        float3 fieldLight = mix(
            float3(0.71, 0.66, 0.76), float3(0.74, 0.64, 0.65), u.warmth);
        float3 fieldDark = mix(
            float3(0.21, 0.17, 0.19), float3(0.25, 0.16, 0.16), u.warmth);
        float3 massColor = u.ink.rgb;
        if (held > 0.0) {
            constexpr sampler pulseSampler(filter::linear, address::repeat);
            float pulse = noise.sample(
                pulseSampler, float3(origin.xy, origin.z + u.time * 0.35)).r - 0.5;
            float flicker = clamp(1.0 + 3.0 * pulse, 0.3, 1.8);
            massColor = mix(u.ink.rgb, fieldDark * smoke, 0.35 * flicker * held);
            float inner = 1.0 - smoothstep(0.0, max(effRadius, 1e-4), length(p));
            massColor = mix(massColor, fieldLight * 0.5, 0.2 * flicker * inner * held);
        }

        float alpha = body * clamp(u.endAlpha, 0.0, 1.0);
        float3 color = mix(u.white.rgb, massColor, alpha);

        // A film grain over the frame, drawn fresh every frame. It rides on the
        // blackness while the mass lives and leaves with the collapse.
        float grain = grainAt(hp * u.screenHeight, u.grainSeed + u.time * 60.0) - 0.5;
        color += grain * 0.03 * alpha * held;
        return float4(color, 1.0);
    }
    """
}
