import Foundation

/// Metal Shading Language source for the simulation core, compiled at startup
/// with `device.makeLibrary(source:)`. SwiftPM cannot build a `.metallib`, and
/// keeping the source in one string lets the headless CLI and the app share it.
/// The kernels match `Core/Programs` row-for-row (verified by `ReadbackSink`
/// tests).
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
        if (gid.x >= p.displayCols || gid.y >= p.displayRows) return;
        uint target = p.displayRows == 1
            ? p.totalSteps - 1
            : (gid.y * (p.totalSteps - 1)) / (p.displayRows - 1);
        colorGrid[gid.y * p.displayCols + gid.x] = fit_value(history, p, target, gid.x);
    }
    """
}
