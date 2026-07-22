#include <metal_stdlib>
using namespace metal;

// Layout must match MeshRenderer.swift's MTLVertexDescriptor and the
// Vertex struct in MeshRenderer.swift exactly. Note: Swift's SIMD3<Float>
// has 16-byte alignment (matching SIMD4, for SIMD register compatibility) even
// though its logical size is 12 bytes, so each SIMD3 field is padded to a
// 16-byte stride — the real per-vertex stride is 48B (16+16+16), not a naively
// packed 40B. MeshRenderer.swift computes all of this dynamically via
// MemoryLayout<...>.stride rather than hardcoding it, so this is handled
// correctly on the Swift side regardless; noted here only so the two files
// don't drift if someone edits the vertex layout later.
struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 color    [[attribute(2)]];
};

struct VertexOut {
    float4 clipPosition [[position]];
    float3 worldNormal;
    float4 color;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3   lightDirection; // world space, points FROM the light
    float    opacity;        // 0...1, spec's opacity slider
};

vertex VertexOut meshVertexShader(VertexIn in [[stage_in]],
                                   constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
    out.clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    out.worldNormal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.color = in.color;
    return out;
}

fragment float4 meshFragmentShader(VertexOut in [[stage_in]],
                                    constant Uniforms &uniforms [[buffer(1)]]) {
    float3 n = normalize(in.worldNormal);
    float diffuse = max(dot(n, normalize(-uniforms.lightDirection)), 0.0);
    // Ambient floor keeps unlit back-faces of the mesh legible rather than
    // going pure black, which matters when orbiting around a scanned wall.
    float lighting = 0.35 + 0.65 * diffuse;
    float3 shaded = in.color.rgb * lighting;
    return float4(shaded, in.color.a * uniforms.opacity);
}

// Flat, unlit variant used for wireframe overlay lines (drawn as a second pass
// with triangleFillMode = .lines) so edges read clearly regardless of lighting.
fragment float4 wireframeFragmentShader(VertexOut in [[stage_in]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
    return float4(0.85, 0.87, 0.9, uniforms.opacity);
}
