import Foundation

/// Mirrors `MeshHeatmap.metal` exactly. This exists as a defensive fallback:
/// Swift Package Manager's handling of `.metal` files via `.process()` (see
/// Package.swift's `resources:` declaration) compiling into a loadable
/// `default.metallib` inside `Bundle.module` is a relatively recent SwiftPM
/// capability, and its behavior can vary across toolchain versions in ways
/// that are hard to verify without a build environment on hand.
///
/// `MeshRenderer` tries the precompiled bundle library first (the normal,
/// preferred path) and only falls back to compiling this source string at
/// runtime via `MTLDevice.makeLibrary(source:options:)` if that fails — so
/// the 3D viewer, which is central to the app, degrades gracefully instead of
/// silently rendering nothing if the resource pipeline doesn't behave as
/// expected on a given Xcode/SwiftPM version.
///
/// IMPORTANT: if you edit `MeshHeatmap.metal`, mirror the change here too.
enum EmbeddedShaderSource {
    static let metalLibrarySource = #"""
    #include <metal_stdlib>
    using namespace metal;

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
        float3   lightDirection;
        float    opacity;
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
        float lighting = 0.35 + 0.65 * diffuse;
        float3 shaded = in.color.rgb * lighting;
        return float4(shaded, in.color.a * uniforms.opacity);
    }

    fragment float4 wireframeFragmentShader(VertexOut in [[stage_in]],
                                             constant Uniforms &uniforms [[buffer(1)]]) {
        return float4(0.85, 0.87, 0.9, uniforms.opacity);
    }
    """#
}
