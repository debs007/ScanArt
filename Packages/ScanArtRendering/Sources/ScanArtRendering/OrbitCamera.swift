import simd
import Foundation

/// Spherical-coordinate orbit camera: rotate (drag), pan (two-finger drag),
/// zoom (pinch), with a perspective/orthographic projection toggle. Drives
/// both the live AR mesh overlay and the offline Analysis 3D viewer.
public struct OrbitCamera {
    public var target: SIMD3<Float>
    public var azimuth: Float      // radians, rotation around Y
    public var elevation: Float    // radians, clamped to avoid gimbal flip
    public var distance: Float
    public var isOrthographic: Bool = false
    public var fovyDegrees: Float = 50
    public var orthoHalfHeight: Float = 1

    public init(target: SIMD3<Float> = .zero, azimuth: Float = .pi / 4, elevation: Float = .pi / 6, distance: Float = 2) {
        self.target = target
        self.azimuth = azimuth
        self.elevation = elevation
        self.distance = distance
    }

    private static let elevationLimit: Float = (.pi / 2) - 0.02

    public mutating func rotate(deltaAzimuth: Float, deltaElevation: Float) {
        azimuth += deltaAzimuth
        elevation = min(max(elevation + deltaElevation, -Self.elevationLimit), Self.elevationLimit)
    }

    public mutating func pan(deltaX: Float, deltaY: Float) {
        let eye = eyePosition
        let forward = normalize(target - eye)
        let right = normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = cross(right, forward)
        let scale = distance * 0.0015
        target += (-right * deltaX + up * deltaY) * scale
    }

    public mutating func zoom(scale: Float) {
        distance = min(max(distance / scale, 0.05), 50)
        orthoHalfHeight = min(max(orthoHalfHeight / scale, 0.02), 25)
    }

    /// Fits the camera to view a bounding box entirely, called when a scan
    /// first loads in the Analysis viewer.
    public mutating func frame(boundingMin: SIMD3<Float>, boundingMax: SIMD3<Float>) {
        target = (boundingMin + boundingMax) / 2
        let extent = length(boundingMax - boundingMin)
        distance = max(extent * 1.4, 0.3)
        orthoHalfHeight = max(extent * 0.6, 0.2)
    }

    public var eyePosition: SIMD3<Float> {
        target + SIMD3<Float>(
            distance * cos(elevation) * sin(azimuth),
            distance * sin(elevation),
            distance * cos(elevation) * cos(azimuth)
        )
    }

    public func viewMatrix() -> simd_float4x4 {
        simd_float4x4(lookAt: eyePosition, target: target, up: SIMD3<Float>(0, 1, 0))
    }

    public func projectionMatrix(aspect: Float, near: Float = 0.01, far: Float = 100) -> simd_float4x4 {
        if isOrthographic {
            let halfWidth = orthoHalfHeight * aspect
            return .orthographic(left: -halfWidth, right: halfWidth, bottom: -orthoHalfHeight, top: orthoHalfHeight, near: near, far: far)
        } else {
            return .perspective(fovyRadians: fovyDegrees * .pi / 180, aspect: aspect, near: near, far: far)
        }
    }
}
