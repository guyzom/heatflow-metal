#include <metal_stdlib>
using namespace metal;

struct Parameters { uint width; uint height; float rx; float ry; };

kernel void heatStep(device const float* src [[buffer(0)]],
                     device float* dst [[buffer(1)]],
                     constant Parameters& p [[buffer(2)]],
                     uint2 xy [[thread_position_in_grid]]) {
    if (xy.x >= p.width || xy.y >= p.height) return;
    uint i = xy.y * p.width + xy.x;
    if (xy.x == 0 || xy.y == 0 || xy.x == p.width - 1 || xy.y == p.height - 1) {
        dst[i] = src[i];
        return;
    }
    float center = src[i];
    dst[i] = center + p.rx * (src[i - 1] - 2 * center + src[i + 1])
        + p.ry * (src[i - p.width] - 2 * center + src[i + p.width]);
}
