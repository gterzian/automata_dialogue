import Foundation

/// Metal Shading Language sources, compiled at startup from strings with the
/// Metal 4 compiler. SwiftPM cannot build a `.metallib`, so the source lives in
/// strings. `simulation` seeds the board and advances it; `layer` compacts the
/// fitted grid into spans and draws them through a GPU-built indirect draw (see
/// `CellGridRenderer`).
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
        uint currentStep;    // source rows computed so far
        uint topRows;        // twin layout: rows from the horizon to an outer edge
        float centreColumn;  // board column at the display's centre
        float sourceStride;  // source cells per display cell in each axis
        uint colors;         // palette entries the cells can hold
        uint toned;          // 1 = a cell covers several source cells; write its colour
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

    // A display cell covers the block of source cells between its own sample
    // position and the next cell's, so the blocks tile the board with no gap and
    // no overlap. At stride 1 a block is one cell and the mapping is exact; past
    // the display floor the stride grows and the block is read at a few evenly
    // spread points. Rows the run has not reached and columns off the board
    // count as background, so a short board grows into the grid and a block at
    // the edge fades toward the page.
    static float column_origin(constant ViewParams& p) {
        return p.centreColumn - float(p.displayCols) * 0.5f * p.sourceStride;
    }

    static int block_start(float origin, int index, float stride) {
        return int(round(origin + float(index) * stride));
    }

    struct BlockCounts {
        uint counts[4];
        uint total;
    };

    // At most three samples per axis, so a long run's stride does not turn the
    // fit into a loop over the whole block: a one- or two-cell block is sampled
    // exactly, a larger one at the centre of evenly spread sub-blocks.
    static BlockCounts block_counts(device const uchar* history, constant ViewParams& p,
                                    int firstRow, int rows, int firstColumn, int columns) {
        BlockCounts result;
        for (uint v = 0; v < 4; ++v) { result.counts[v] = 0; }
        result.total = 0;
        if (rows <= 0 || columns <= 0) { return result; }
        // The catalog's automata have two or three states; a palette index above
        // the last one cannot occur.
        uint values = min(p.colors, 4u);
        uint rowTaps = uint(min(rows, 3));
        uint columnTaps = uint(min(columns, 3));
        for (uint r = 0; r < rowTaps; ++r) {
            int row = firstRow + int((float(r) + 0.5f) * float(rows) / float(rowTaps));
            for (uint c = 0; c < columnTaps; ++c) {
                int column = firstColumn
                    + int((float(c) + 0.5f) * float(columns) / float(columnTaps));
                uchar value = 0;
                if (row >= 0 && row <= int(p.currentStep)
                    && column >= 0 && column < int(p.boardWidth)) {
                    value = history[uint(row) % p.capacity * p.boardWidth + uint(column)];
                }
                result.counts[min(uint(value), values - 1)] += 1;
                result.total += 1;
            }
        }
        return result;
    }

    // The block's most common value, for a cell that is one source cell. Ties go
    // to the lower index, which keeps a block that is half background background.
    static uchar majority(BlockCounts b, uint values) {
        uint best = 0;
        for (uint v = 1; v < values; ++v) {
            if (b.counts[v] > b.counts[best]) { best = v; }
        }
        return uchar(best);
    }

    // The block's average palette colour, for a cell that covers several source
    // cells. Voting would erase a sparse pattern — most of its blocks hold no
    // ink — and would beat against the automaton's own lattice, so below the
    // floor the cell keeps every state's share of the block instead of one
    // winner, and the draw resolves the average as tone.
    static uchar4 average(BlockCounts b, constant const float4* palette) {
        float4 sum = float4(0.0);
        for (uint v = 0; v < 4; ++v) { sum += palette[v] * float(b.counts[v]); }
        float4 color = clamp(sum / float(max(b.total, 1u)), 0.0f, 1.0f);
        return uchar4(color * 255.0f + 0.5f);
    }

    // One display cell in the frame's own format: a palette index above the
    // floor and the block's average colour below it.
    static void write_cell(device uchar* colorGrid, constant ViewParams& p, uint slot,
                           BlockCounts counts, constant const float4* palette) {
        if (p.toned == 0) {
            colorGrid[slot] = majority(counts, min(p.colors, 4u));
            return;
        }
        device uchar4* colors = (device uchar4*)colorGrid;
        colors[slot] = average(counts, palette);
    }

    // The board column display cell `x` samples when one cell is one block. The
    // twin layout's horizon row uses this lattice, so the seed row stays exact
    // at every stride.
    static bool sample_column(constant ViewParams& p, uint x, thread uint& column) {
        float source = p.centreColumn
            + (float(x) - float(p.displayCols) * 0.5f) * p.sourceStride;
        if (source < 0.0f || source >= float(p.boardWidth)) { return false; }
        column = uint(round(source));
        return column < p.boardWidth;
    }

    kernel void fit(device const uchar* history [[buffer(0)]],
                    device uchar* colorGrid [[buffer(1)]],
                    constant ViewParams& p [[buffer(2)]],
                    constant float4* palette [[buffer(3)]],
                    uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.displayCols || gid.y >= p.displayRows) return;
        float origin = column_origin(p);
        int firstRow = block_start(0.0f, int(gid.y), p.sourceStride);
        int firstColumn = block_start(origin, int(gid.x), p.sourceStride);
        BlockCounts counts = block_counts(
            history, p, firstRow,
            block_start(0.0f, int(gid.y) + 1, p.sourceStride) - firstRow,
            firstColumn,
            block_start(origin, int(gid.x) + 1, p.sourceStride) - firstColumn);
        write_cell(colorGrid, p, gid.y * p.displayCols + gid.x, counts, palette);
    }

    // The reveal's mirrored pair: one shared horizon row at the centre, with
    // the upper branch growing up from it and the lower branch growing down
    // from the same row. `p.topRows` is the distance from the horizon to each
    // outer edge. The seed row stays on the horizon and the newest source row
    // on both outer edges as the sampling stride grows, so the whole growth
    // stays in view; the horizon row is written once.
    kernel void fit_twin(device const uchar* history [[buffer(0)]],
                         device uchar* colorGrid [[buffer(1)]],
                         constant ViewParams& p [[buffer(2)]],
                         constant float4* palette [[buffer(3)]],
                         uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.displayCols || gid.y >= p.displayRows) return;
        uint halfRows = p.topRows;
        uint local = gid.y <= halfRows ? (halfRows - gid.y) : (gid.y - halfRows);
        uint slot = gid.y * p.displayCols + gid.x;
        if (local == 0) {
            // The horizon is the axis both branches mirror around and the frame
            // the intro hands over, so it keeps the seed row exactly rather than
            // reducing its block.
            uint column = 0;
            uchar value = 0;
            if (sample_column(p, gid.x, column)) { value = history[column]; }
            BlockCounts exact;
            for (uint v = 0; v < 4; ++v) { exact.counts[v] = 0; }
            exact.counts[min(uint(value), 3u)] = 1;
            exact.total = 1;
            write_cell(colorGrid, p, slot, exact, palette);
            return;
        }
        float origin = column_origin(p);
        int firstRow = block_start(0.0f, int(local), p.sourceStride);
        int firstColumn = block_start(origin, int(gid.x), p.sourceStride);
        BlockCounts counts = block_counts(
            history, p, firstRow,
            block_start(0.0f, int(local) + 1, p.sourceStride) - firstRow,
            firstColumn,
            block_start(origin, int(gid.x) + 1, p.sourceStride) - firstColumn);
        write_cell(colorGrid, p, slot, counts, palette);
    }
    """

    public static let layer = """
    #include <metal_stdlib>
    using namespace metal;

    // One horizontal run of same-colour, non-background cells (draw cost
    // follows the structure). Layout mirrors `CellGridRenderer.Span`.
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

    /// The below-floor minification: cells that are already colours, drawn as
    /// one full-surface sample. A toned cell has no palette index to compact
    /// into a span, and stippling the cell's coverage back into indices would
    /// cost a span for every ink cell, so the tone grid is sampled directly.
    public static let tone = """
    #include <metal_stdlib>
    using namespace metal;

    struct ToneOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex ToneOut tone_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        ToneOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        // The grid's first row is the top of the image, so v runs against the
        // surface's y.
        out.uv = float2(positions[vid].x * 0.5 + 0.5, 0.5 - positions[vid].y * 0.5);
        return out;
    }

    fragment float4 tone_fragment(ToneOut in [[stage_in]],
                                  texture2d<float> cells [[texture(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        return cells.sample(s, in.uv);
    }
    """

    /// The submission beat between Return and the intro: the submitted image
    /// separates into a double exposure — two copies a fraction of the image's
    /// height apart — then the doubled screen falls into the intro's opening
    /// dot. `SubmissionTimeline` owns its timing.
    public static let submission = """
    #include <metal_stdlib>
    using namespace metal;

    struct SubmissionUniforms {
        float aspect;
        float imageAspect;
        float doubling;
        float collapse;
        float dotScale;
        float lineHalfThickness;
        float screenHeight;
        float4 white;
        float4 ink;
    };

    struct SubmissionOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex SubmissionOut submission_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        SubmissionOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.uv = positions[vid] * 0.5 + 0.5;
        return out;
    }

    // A point outside the fitted image has alpha 0, so the page shows through.
    static float4 sampleFitted(texture2d<float> image, sampler s, float2 p,
                               float2 fit, float2 origin) {
        float2 local = (p - origin) / fit;
        if (any(local < 0.0) || any(local > 1.0)) { return float4(0.0); }
        return float4(image.sample(s, local).rgb, 1.0);
    }

    fragment float4 submission_fragment(SubmissionOut in [[stage_in]],
                                        constant SubmissionUniforms& u [[buffer(0)]],
                                        texture2d<float> image [[texture(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        // p is screen coordinates with y down, so the clones' directions match
        // the view's.
        float2 p = float2(in.uv.x, 1.0 - in.uv.y);

        float screenAspect = u.aspect;
        float imageAspect = u.imageAspect;
        float2 fit = float2(1.0);
        if (imageAspect > screenAspect) {
            fit.y = screenAspect / imageAspect;
        } else {
            fit.x = imageAspect / screenAspect;
        }
        float2 origin = (1.0 - fit) * 0.5;

        // A double exposure rather than two images leaving the frame: the copies
        // separate by a fraction of the image's own height, then return to zero
        // as the doubled screen collapses, so they merge back together on the way
        // into the dot. Both are sampled at the same source point when the offset
        // is zero, so the first frame is the image and the last is the dot.
        float parting = 0.2 * fit.y * u.doubling * (1.0 - u.collapse);

        // The same point pulled toward the centre shrinks the doubled screen
        // into the dot. At collapse 0 it is p itself, so the phases join.
        float cover = length(float2(u.aspect, 1.0)) * 0.5 + 0.15;
        float px = 1.0 / max(u.screenHeight, 1.0);
        float dotR = max(u.lineHalfThickness * 3.0, 2.5 * px) * u.dotScale;
        float scale = mix(1.0, dotR / cover, u.collapse);
        float2 q = 0.5 + (p - 0.5) / scale;

        float4 a = sampleFitted(image, s, float2(q.x, q.y + parting), fit, origin);
        float4 b = sampleFitted(image, s, float2(q.x, q.y - parting), fit, origin);
        float total = a.a + b.a;
        float3 scene = total > 0.0 ? (a.rgb * a.a + b.rgb * b.a) / total : u.white.rgb;

        // The dot is the intro's opening dot: the same radius, colour, and
        // centre, so the handoff has no jump.
        float2 hp = (p - 0.5) * float2(u.aspect, 1.0);
        float soft = max(dotR * 0.5, 1.5 * px);
        float dot = 1.0 - smoothstep(-soft, soft, length(hp) - dotR);
        float dotAlpha = smoothstep(0.55, 1.0, u.collapse);
        float3 color = mix(scene, u.ink.rgb, dot * dotAlpha);
        return float4(color, 1.0);
    }
    """

    /// The intro the review window shows while the model's turn is prepared;
    /// `CollapseTimeline` owns its timing and `CollapseVariation` its look.
    /// Everything is drawn by one full-screen fragment shader: the layers, the
    /// dot and line, and the grain. No offscreen targets or upsample are needed;
    /// the shader writes the surface directly.
    public static let collapse = """
    #include <metal_stdlib>
    using namespace metal;

    struct CollapseUniforms {
        float time;
        float aspect;
        float screenHeight;
        float noiseScale;
        float smokeStrength;
        float noiseX;
        float noiseY;
        float noiseZ;
        float warmth;
        float grainSeed;
        float dotScale;
        float endAlpha;
        float wobble;
        float haloScale;
        float stretch;
        float lineHalfThickness;
        float settle;
        float4 grow;
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

    // Smooth noise read at the pixel position. Its low frequency bends the whole
    // distance field gently, so each circle's edge undulates like ink in water.
    static float edgeNoise(texture3d<float> noise, float2 p, float t, float scale,
                           float3 origin) {
        constexpr sampler s(filter::linear, address::repeat);
        return noise.sample(
            s, float3(p * scale + origin.xy + float2(t * 0.02, -t * 0.015),
                      origin.z + t * 0.03)).r - 0.5;
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
        float px = 1.0 / max(u.screenHeight, 1.0);
        float live = 1.0 - u.stretch;

        float cover = length(float2(u.aspect, 1.0)) * 0.5 + 0.15;
        // The resting line is a hairline so it barely shows; the retraction
        // thickens it back to the seed cell it lands on.
        float startR = max(u.lineHalfThickness * 3.0, 2.5 * px) * u.dotScale;
        float lineR = mix(u.lineHalfThickness * 0.35, u.lineHalfThickness, u.settle);
        float dotR = mix(startR, lineR, u.stretch);

        // Every layer is centred on the frame, so the dot never moves between
        // runs and the resting line stays on the reveal's horizon row.
        float2 p = hp;

        // One warped distance serves every circle, so the layers undulate together.
        float breathing = 1.0 + 0.012 * sin(u.time * 2.1 + u.grainSeed);
        float warp = (1.0 + 2.0 * u.wobble
                      * edgeNoise(noise, p, u.time, u.noiseScale * 1.5, origin)) * breathing;
        float d = length(p) / mix(1.0, warp, live);

        float3 fieldLight = mix(float3(0.78, 0.72, 0.80), float3(0.82, 0.70, 0.68), u.warmth);
        float3 fieldDark = mix(float3(0.30, 0.25, 0.28), float3(0.34, 0.24, 0.23), u.warmth);
        float smoke = mix(
            1.0, 0.75 + 0.5 * smokeValue(noise, p, u.time, u.noiseScale, origin),
            u.smokeStrength);
        constexpr sampler pulseSampler(filter::linear, address::repeat);
        float pulse = noise.sample(
            pulseSampler, float3(origin.xy, origin.z + u.time * 0.35)).r - 0.5;
        float flicker = clamp(1.0 + 1.2 * pulse, 0.7, 1.3);

        float peaks[3] = { cover, cover, cover * u.haloScale };
        float softness[3] = { 0.06, 0.10, 0.24 };

        float3 color = u.white.rgb;
        for (int k = 0; k < 3; ++k) {
            float g = u.grow[k];
            if (g <= 0.0) { continue; }
            // The sphere and the white hole grow geometrically from the dot;
            // the rings carry a radius fraction so their size eases evenly
            // instead of popping out near the end of the rise.
            float R = k < 2 ? dotR * pow(peaks[k] / dotR, g)
                            : mix(dotR, peaks[k], g);
            float soft = max(R * softness[k], 1.5 * px);
            float body = 1.0 - smoothstep(-soft, soft, d - R);
            float presence = smoothstep(0.0, 0.03, g);
            if (k == 0) { presence *= clamp(u.endAlpha, 0.0, 1.0); }

            float3 tone = u.white.rgb;           // odd layers: white
            if (k % 2 == 0) {                    // even layers: sphere
                float r = clamp(d / max(R, 1e-4), 0.0, 1.0);
                float3 shade = mix(fieldLight, fieldDark, pow(r, 1.4));
                if (k == 0) { shade *= smoke * flicker; }
                // A small sphere is ink; the gradient appears as it grows.
                tone = mix(u.ink.rgb, shade, smoothstep(0.01, 0.12, R / cover));
            }
            color = mix(color, tone, body * presence);
        }

        // The dot sits over the mass and becomes the horizon line. The white
        // ring is painted after it, so the line reads through the dark halo
        // and stops at the ring, as it does in the reference.
        float2 q = float2(max(abs(p.x) - u.stretch * (u.aspect * 0.5 + 0.05), 0.0), p.y);
        // The finale retracts the line onto the reveal's seed: one cell, half a
        // cell right of the frame's centre, as tall as the horizon row.
        float2 cell = p - float2(u.lineHalfThickness, 0.0);
        float dist = mix(length(q), max(abs(cell.x), abs(cell.y)), u.settle);
        float dotSoft = max(dotR * 0.5, mix(1.5 * px, 0.5 * px, u.stretch));
        float dotBody = 1.0 - smoothstep(-dotSoft, dotSoft, dist - dotR);
        color = mix(color, u.ink.rgb, dotBody * clamp(u.endAlpha, 0.0, 1.0));

        // The white ring and the inner sphere sit on top, so the dot the cycle
        // started from becomes the nested sphere at the centre of the rings.
        if (u.grow.w > 0.0) {
            float R = mix(dotR, cover * u.haloScale * 0.5, u.grow.w);
            float soft = max(R * 0.05, 1.5 * px);
            float body = 1.0 - smoothstep(-soft, soft, d - R);
            float presence = smoothstep(0.0, 0.03, u.grow.w);
            color = mix(color, u.white.rgb, body * presence);
        }
        if (u.grow.z > 0.0) {
            float R = mix(dotR, cover * u.haloScale * 0.17, u.grow.z);
            float soft = max(R * 0.08, 1.5 * px);
            float body = 1.0 - smoothstep(-soft, soft, d - R);
            float presence = smoothstep(0.0, 0.03, u.grow.z);
            float r = clamp(d / max(R, 1e-4), 0.0, 1.0);
            float3 shade = mix(fieldLight, fieldDark, pow(r, 1.4));
            color = mix(color, shade, body * presence);
        }

        // Film grain rides on the dark areas and leaves as the dot stretches.
        float darkness = clamp(1.0 - dot(color, float3(1.0 / 3.0)), 0.0, 1.0);
        float grain = grainAt(hp * u.screenHeight, u.grainSeed + u.time * 60.0) - 0.5;
        color += grain * 0.04 * darkness * darkness * live;
        return float4(color, 1.0);
    }
    """
}
