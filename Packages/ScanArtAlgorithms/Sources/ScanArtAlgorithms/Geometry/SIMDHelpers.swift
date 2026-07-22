import simd

/// Small, focused extensions on top of Apple's `simd` module.
/// Everything here is a pure function on value types — safe to call from any thread.
public extension SIMD4 where Scalar == Float {
    /// Drops the `w` component. Useful after transforming a homogeneous point/vector.
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

public extension simd_float4x4 {
    /// Transforms a point (implicit w = 1). Applies translation.
    func transformPoint(_ p: SIMD3<Float>) -> SIMD3<Float> {
        (self * SIMD4<Float>(p, 1)).xyz
    }

    /// Transforms a direction/normal (implicit w = 0). Ignores translation.
    /// Note: for non-uniform scale you'd want the inverse-transpose here; ARKit
    /// anchor transforms are rigid (rotation + translation only), so this is exact.
    func transformDirection(_ d: SIMD3<Float>) -> SIMD3<Float> {
        (self * SIMD4<Float>(d, 0)).xyz
    }

    /// Builds a right-handed look-at view matrix.
    init(lookAt eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        self.init(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }

    /// Metal-style perspective projection (clip-space Z in [0, 1]).
    static func perspective(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1 / tan(fovyRadians * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = far / zRange
        let wzScale = -near * far / zRange
        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, 1),
            SIMD4<Float>(0, 0, wzScale, 0)
        ))
    }

    /// Metal-style orthographic projection (clip-space Z in [0, 1]).
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
        let sx = 2 / (right - left)
        let sy = 2 / (top - bottom)
        let sz = 1 / (far - near)
        let tx = -(right + left) / (right - left)
        let ty = -(top + bottom) / (top - bottom)
        let tz = -near / (far - near)
        return simd_float4x4(columns: (
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, sz, 0),
            SIMD4<Float>(tx, ty, tz, 1)
        ))
    }

    /// 4x4 identity, spelled out for readability at call sites.
    static var identity: simd_float4x4 { matrix_identity_float4x4 }

    /// Flattens column-major into a 16-element array (for persistence in SwiftData).
    var flattened: [Double] {
        let c = columns
        return [Double(c.0.x), Double(c.0.y), Double(c.0.z), Double(c.0.w),
                Double(c.1.x), Double(c.1.y), Double(c.1.z), Double(c.1.w),
                Double(c.2.x), Double(c.2.y), Double(c.2.z), Double(c.2.w),
                Double(c.3.x), Double(c.3.y), Double(c.3.z), Double(c.3.w)]
    }

    /// Reconstructs a matrix from a flattened array produced by `flattened`.
    init?(flattened values: [Double]) {
        guard values.count == 16 else { return nil }
        let f = values.map(Float.init)
        self.init(columns: (
            SIMD4<Float>(f[0], f[1], f[2], f[3]),
            SIMD4<Float>(f[4], f[5], f[6], f[7]),
            SIMD4<Float>(f[8], f[9], f[10], f[11]),
            SIMD4<Float>(f[12], f[13], f[14], f[15])
        ))
    }
}
