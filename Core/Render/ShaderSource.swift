import Foundation

/// Metal Shading Language sources, compiled at startup from strings with the
/// Metal 4 compiler. SwiftPM cannot build a `.metallib`, and keeping the source
/// in strings lets the headless CLI and the app share it. `simulation` matches
/// `Core/Programs` row-for-row; `layer` compacts the fitted grid into spans and
/// draws them through a GPU-built indirect draw (see `LayerRenderer`).
public enum ShaderSource {
    public static let simulation = """
    #include <metal_stdlib>
    using namespace metal;

    struct StepParams {
        uint width;
        uint rule;    // elementary rule bits, or totalistic code
        uint colors;  // 0 selects the elementary kernel
    };

    struct FitParams {
        uint boardWidth;
        uint displayCols;
        uint displayRows;
        uint totalSteps;
        uint block;
        uint sourceOrigin;
        uint padLeft;
        uint rowOffset;
    };

    // The row being computed is read from a GPU-side head counter that
    // `bump_head` advances, so every dispatch in the run binds the same
    // buffers (design doc §11.9 fallback). The argument table is live at GPU
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
        uint base = readRow * p.width;
        uint l = history[base + (i + p.width - 1) % p.width];
        uint c = history[base + i];
        uint r = history[base + (i + 1) % p.width];
        uint neighborhood = (l << 2) | (c << 1) | r;
        history[writeRow * p.width + i] = uchar((p.rule >> neighborhood) & 1u);
    }

    kernel void step_totalistic(device uchar* history [[buffer(0)]],
                                constant StepParams& p [[buffer(1)]],
                                device const uint* head [[buffer(2)]],
                                uint gid [[thread_position_in_grid]]) {
        if (gid >= p.width) return;
        uint readRow = *head;
        uint writeRow = readRow + 1;
        uint i = gid;
        uint base = readRow * p.width;
        uint l = history[base + (i + p.width - 1) % p.width];
        uint c = history[base + i];
        uint r = history[base + (i + 1) % p.width];
        uint sum = l + c + r;
        uint divisor = 1;
        for (uint k = 0; k < sum; ++k) { divisor *= p.colors; }
        history[writeRow * p.width + i] = uchar((p.rule / divisor) % p.colors);
    }

    kernel void bump_head(device uint* head [[buffer(0)]],
                          uint gid [[thread_position_in_grid]]) {
        if (gid == 0) { *head = *head + 1; }
    }

    // Nearest for a single-cell block; majority vote (ties to the smaller
    // palette index) when downsampling. Out-of-board columns read background.
    static uchar fit_value(device const uchar* history, constant FitParams& p,
                           uint sourceStep, uint displayCol) {
        uint base = sourceStep * p.boardWidth;
        if (p.boardWidth < p.displayCols) {
            int idx = int(displayCol) - int(p.padLeft);
            if (idx < 0 || idx >= int(p.boardWidth)) return 0;
            return history[base + uint(idx)];
        }
        uint counts[4] = {0, 0, 0, 0};
        uint total = 0;
        for (uint offset = 0; offset < p.block; ++offset) {
            uint idx = p.sourceOrigin + displayCol * p.block + offset;
            if (idx >= p.boardWidth) continue;
            uchar value = history[base + idx];
            if (value < 4) counts[value] += 1;
            total += 1;
        }
        if (total == 0) return 0;
        uchar best = 0;
        uint bestCount = 0;
        for (uint v = 0; v < 4; ++v) {
            if (counts[v] > bestCount) { bestCount = counts[v]; best = uchar(v); }
        }
        return best;
    }

    kernel void fit(device const uchar* history [[buffer(0)]],
                    device uchar* colorGrid [[buffer(1)]],
                    constant FitParams& p [[buffer(2)]],
                    uint2 gid [[thread_position_in_grid]]) {
        uint row = p.rowOffset + gid.y;
        if (gid.x >= p.displayCols || row >= p.displayRows) return;
        uint target = p.displayRows == 1
            ? p.totalSteps - 1
            : (row * (p.totalSteps - 1)) / (p.displayRows - 1);
        colorGrid[row * p.displayCols + gid.x] = fit_value(history, p, target, gid.x);
    }
    """

    public static let layer = """
    #include <metal_stdlib>
    using namespace metal;

    // One horizontal run of same-colour, non-background cells (design doc §6:
    // draw cost follows the structure). Layout mirrors `LayerRenderer.Span`.
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

    // One instance per span; six vertices form the quad. Row 0 is the top edge,
    // matching `IncrementalRenderer`'s top-down grid.
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
}
