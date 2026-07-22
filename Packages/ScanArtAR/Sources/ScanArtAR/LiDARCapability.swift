import ARKit

/// The spec's device gate: "detect LiDAR availability before starting; if
/// unavailable show 'This device is not supported.'" Checked at Splash/Home
/// so no scan flow is ever entered on unsupported hardware.
public enum LiDARCapability {
    /// True on iPhone Pro / iPad Pro models with a LiDAR Scanner (and any
    /// future device ARKit reports as supporting mesh scene reconstruction).
    /// Deliberately checks capability rather than maintaining a hardcoded
    /// device-model allowlist, which would silently go stale on new hardware.
    public static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    public static var supportsClassification: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }
}
