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

    /// The expanding-and-collapsing intro the review window shows while the
    /// model runs: a point grows into a shaded disc, whites out, opens into
    /// nested discs and rays, fills with a starburst, goes black, and shrinks
    /// that black field into the final white page.
    ///
    /// Everything is drawn by one full-screen fragment shader: the mottled
    /// field, the back discs, the rays, the starburst, the front bullseye, and
    /// the final black-to-white shrink. No offscreen targets or upsample are
    /// needed; the shader writes the drawable directly.
    public static let collapse = """
    #include <metal_stdlib>
    using namespace metal;

    struct CollapseUniforms {
        float time;
        float aspect;
        float screenHeight;
        float fieldAlpha;
        float burstAlpha;
        float burstRotation;
        float burstWidth;
        float burstLight;
        float blackout;
        float shrinkMix;
        float shrinkRadius;
        float dotRadius;
        float dotOpacity;
        float noiseScale;
        float smokeStrength;
        float discCount;
        float rayCount;
        float centerX;
        float centerY;
        float warp;
        float noiseX;
        float noiseY;
        float noiseZ;
        float warmth;
        float burstSectors;
        float grainSeed;
        float4 white;
        float4 ink;
    };

    struct CollapseDisc {
        float radius;
        float fillMode;      // 0 white, 1 shaded, 2 ring only, 3 soft glow
        float rimWidth;
        float rimDark;
        float penumbraWidth;
        float penumbraDark;
        float opacity;
        float layer;         // 0 behind the rays, 1 in front
        float fillDark;
    };

    struct CollapseRay {
        float angle;
        float halfWidth;
        float length;
        float darkness;
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

    // The contour's wander. The volume is smooth at this scale, so a disc's
    // edge drifts in and out; sampling the unsmoothed volume would scallop
    // every edge at the texel boundary instead.
    static float contourWander(texture3d<float> noise, float2 p, float t,
                               float3 origin) {
        constexpr sampler s(filter::linear, address::repeat);
        float a = noise.sample(s, float3(p * 0.09 + origin.xy, origin.z + t * 0.015)).r;
        float b = noise.sample(s, float3(p * 0.22 + origin.yx, origin.z + 0.57 + t * 0.025)).r;
        return (a - 0.5) * 0.8 + (b - 0.5) * 0.2;
    }

    // Per-pixel white noise for the film grain; the seed moves each frame.
    static float grainAt(float2 pixel, float seed) {
        float3 p3 = fract(float3(pixel.xyx) * float3(0.1031, 0.1030, 0.0973));
        p3 += dot(p3, p3.yzx + 33.33 + seed);
        return fract((p3.x + p3.y) * p3.z);
    }

    // `d` is the wandering radius, `smoke` the field's texture at this pixel.
    // Every edge is feathered over a fraction of its own radius, so the discs
    // read as painted light rather than as vector circles.
    static float3 shadeDisc(float3 color, float2 p, float d, float smoke, float warmth,
                            constant CollapseDisc& disc) {
        float aa = max(fwidth(d), 1e-5);
        float soft = max(aa, disc.radius * 0.05 + 0.0012);
        if (disc.fillMode > 2.5) {
            float glow = 1.0 - smoothstep(0.0, max(disc.radius, 1e-5), d);
            glow *= glow;
            float strength = clamp(glow * disc.opacity * (1.0 + 0.3 * (smoke - 1.0)), 0.0, 1.0);
            return mix(color, float3(1.0), strength);
        }
        float s = d - disc.radius;
        float fill = 1.0 - smoothstep(-soft, soft, s);
        float rim = 1.0 - smoothstep(disc.rimWidth, disc.rimWidth + soft * 1.6, abs(s));
        float pen = disc.penumbraDark * exp(-max(s, 0.0) / max(disc.penumbraWidth, 1e-5));
        color *= 1.0 - clamp(pen * disc.opacity * (1.0 + 0.5 * (smoke - 1.0)), 0.0, 1.0);
        if (disc.fillMode < 1.5) {
            float3 fillColor;
            if (disc.fillMode < 0.5) {
                fillColor = float3(0.97) + 0.06 * (smoke - 0.5);
            } else {
                float radial = clamp(d / max(disc.radius, 1e-5), 0.0, 1.0);
                float3 lit = mix(
                    float3(0.80, 0.76, 0.85), float3(0.82, 0.75, 0.74), warmth);
                // A soft highlight sits off-centre, so the fill turns like a
                // lit object instead of a concentric gradient.
                float2 offset = p / max(disc.radius, 1e-5) - float2(0.16, 0.20);
                float highlight = exp(-dot(offset, offset) * 1.6);
                fillColor = mix(
                    lit,
                    float3(disc.fillDark, disc.fillDark * 0.86, disc.fillDark * 0.85),
                    smoothstep(0.0, 1.05, radial));
                fillColor = mix(fillColor, lit * 1.06, highlight * 0.4);
                fillColor *= 1.0 + 0.35 * (smoke - 1.0);
            }
            color = mix(color, fillColor, clamp(fill * disc.opacity, 0.0, 1.0));
        }
        if (disc.rimWidth > 0.0) {
            float3 rimColor = mix(
                float3(0.21, 0.16, 0.19), float3(0.25, 0.16, 0.16), warmth);
            color = mix(color, rimColor * (1.0 + 0.24 * (smoke - 1.0)),
                        clamp(rim * disc.rimDark * disc.opacity, 0.0, 1.0));
        }
        return color;
    }

    fragment float4 collapse_fragment(FullscreenOut in [[stage_in]],
                                      constant CollapseUniforms& u [[buffer(0)]],
                                      constant CollapseDisc* discs [[buffer(1)]],
                                      constant CollapseRay* rays [[buffer(2)]],
                                      texture3d<float> noise [[texture(0)]]) {
        float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0) - float2(u.centerX, u.centerY);
        float r = length(p);
        float angle = atan2(p.y, p.x);
        float3 origin = float3(u.noiseX, u.noiseY, u.noiseZ);
        float smoke = mix(
            1.0, 0.75 + 0.5 * smokeValue(noise, p, u.time, u.noiseScale, origin),
            u.smokeStrength);
        // Every circle is measured against this one wandering radius. The small
        // constant term keeps the wander visible at the opening point's scale,
        // where a purely proportional wobble would round away.
        float wander = contourWander(noise, p, u.time, origin);
        float d = r * (1.0 + u.warp * 2.0 * wander) + u.warp * 0.35 * wander;

        float3 color = u.white.rgb;

        // Mottled rose field, darkest at the corners.
        float3 fieldLight = mix(
            float3(0.71, 0.66, 0.76), float3(0.74, 0.64, 0.65), u.warmth);
        float3 fieldDark = mix(
            float3(0.21, 0.17, 0.19), float3(0.25, 0.16, 0.16), u.warmth);
        float fieldMask = smoothstep(0.25, 1.1, d);
        float3 field = mix(fieldLight, fieldDark, fieldMask) * smoke;
        color = mix(color, field, u.fieldAlpha);

        int discCount = int(u.discCount);
        int rayCount = int(u.rayCount);

        // Large discs first.
        for (int i = 0; i < 9; ++i) {
            if (i >= discCount) { break; }
            if (discs[i].layer < 0.5) {
                color = shadeDisc(color, p, d, smoke, u.warmth, discs[i]);
            }
        }

        // Rays sit above the large discs and below the center bullseye. The
        // field's texture thins them along their length.
        for (int i = 0; i < 8; ++i) {
            if (i >= rayCount) { break; }
            float fraction = fract((angle - rays[i].angle) / 6.2831853 + 0.5);
            float delta = abs(fraction - 0.5) * 6.2831853;
            float across = delta / max(rays[i].halfWidth, 1e-5);
            float alpha = rays[i].darkness
                * (1.0 - smoothstep(0.0, 1.0, abs(across)))
                * (1.0 - smoothstep(rays[i].length * 0.85, rays[i].length, d))
                * (1.0 + 0.6 * (smoke - 1.0));
            float3 rayColor = mix(
                float3(0.20, 0.16, 0.19), float3(0.22, 0.15, 0.15), u.warmth);
            color = mix(color, rayColor, clamp(alpha, 0.0, 1.0));
        }

        // The late starburst alternates dark and light wedges. The field's
        // texture roughens the wedge edges, so the fan looks scratched rather
        // than cut.
        float sectorSize = 6.2831853 / max(u.burstSectors, 1.0);
        float sectorCoord = (angle - u.burstRotation) / sectorSize + (smoke - 1.0) * 0.45;
        float sector = fract(sectorCoord);
        float sectorAA = fwidth(sectorCoord) * 1.5;
        float darkWedge = 1.0 - smoothstep(0.30, u.burstWidth + sectorAA, abs(sector - 0.25));
        float lightWedge = 1.0 - smoothstep(0.30, u.burstWidth + sectorAA, abs(sector - 0.75));
        float3 burstDark = mix(
            float3(0.21, 0.16, 0.20), float3(0.25, 0.16, 0.16), u.warmth);
        float3 burstLight = mix(
            float3(0.84, 0.80, 0.88), float3(0.88, 0.80, 0.81), u.warmth);
        color = mix(color, burstDark, clamp(darkWedge * u.burstAlpha, 0.0, 1.0));
        color = mix(
            color, burstLight, clamp(lightWedge * u.burstAlpha * u.burstLight, 0.0, 1.0));

        // Center discs and rings cover the rays where they converge.
        for (int i = 0; i < 9; ++i) {
            if (i >= discCount) { break; }
            if (discs[i].layer > 0.5) {
                color = shadeDisc(color, p, d, smoke, u.warmth, discs[i]);
            }
        }

        // The starburst goes mostly black. That black field then shrinks into
        // a white page with a final ink point that shrinks away; the field
        // fades out as its radius reaches zero, so the page ends clean.
        float aa = max(0.0025, 0.75 / max(u.screenHeight, 1.0));
        color = mix(color, float3(0.0), clamp(u.blackout, 0.0, 1.0));
        float shrinkSoft = max(u.shrinkRadius * 0.10, aa * 1.5);
        float shrinkMask = smoothstep(0.0, shrinkSoft * 4.0, u.shrinkRadius);
        float black = (1.0 - smoothstep(u.shrinkRadius - shrinkSoft,
                                        u.shrinkRadius + shrinkSoft, d)) * shrinkMask;
        float3 page = mix(u.white.rgb, u.ink.rgb, clamp(black, 0.0, 1.0));
        // A small white point stays visible inside the shrinking black field
        // and disappears with it.
        float highlightRadius = u.shrinkRadius * 0.32;
        float highlight = u.shrinkRadius > 0.001
            ? (1.0 - smoothstep(
                max(highlightRadius - aa, 0.0), highlightRadius + aa, d)) * shrinkMask
            : 0.0;
        page = mix(page, u.white.rgb, highlight * 0.9);
        color = mix(color, page, clamp(u.shrinkMix, 0.0, 1.0));

        // The opening point is a small dense mound, not a flat coin: an uneven
        // feathered edge, a wide faint penumbra, and a middle that lightens
        // toward the field's colour.
        float dotSoft = max(u.dotRadius * 0.35, 1.5 / max(u.screenHeight, 1.0));
        float dot = u.dotRadius > 0.0
            ? 1.0 - smoothstep(max(u.dotRadius - dotSoft, 0.0), u.dotRadius + dotSoft, d)
            : 0.0;
        float halo = u.dotRadius > 0.0
            ? 1.0 - smoothstep(u.dotRadius, u.dotRadius + dotSoft * 5.0, d)
            : 0.0;
        float core = 1.0 - smoothstep(0.0, max(u.dotRadius, 1e-5), d);
        float3 dotColor = mix(
            u.ink.rgb,
            mix(float3(0.30, 0.26, 0.30), float3(0.34, 0.26, 0.27), u.warmth),
            smoothstep(0.1, 0.85, core));
        float dotOpacity = clamp(u.dotOpacity, 0.0, 1.0);
        color = mix(color, dotColor,
                    max(dot * dotOpacity, halo * 0.35 * dotOpacity));

        // A film grain over the whole frame, drawn fresh every frame.
        float2 pixel = in.uv * float2(u.aspect, 1.0) * u.screenHeight;
        float grain = grainAt(pixel, u.grainSeed + u.time * 60.0) - 0.5;
        color += grain * 0.035;
        return float4(color, 1.0);
    }
    """
}
