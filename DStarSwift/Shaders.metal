#include <metal_stdlib>
using namespace metal;

struct StarVertex {
    float3 position;
    float4 color;
};

struct Uniforms {
    float4x4 viewProjection;
};

struct StarOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

vertex StarOut starVertex(
    uint vid [[vertex_id]],
    const device StarVertex *vertices [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    StarVertex v = vertices[vid];
    StarOut out;
    out.position = uniforms.viewProjection * float4(v.position, 1.0);
    out.color = v.color;
    out.pointSize = 2.5;
    return out;
}

fragment float4 starFragment(StarOut in [[stage_in]]) {
    return in.color;
}

struct MeshOut {
    float4 position [[position]];
    float4 color;
};

vertex MeshOut meshVertex(
    uint vid [[vertex_id]],
    const device StarVertex *vertices [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    StarVertex v = vertices[vid];
    MeshOut out;
    out.position = uniforms.viewProjection * float4(v.position, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 meshFragment(MeshOut in [[stage_in]]) {
    return in.color;
}
