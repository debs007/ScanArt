import SwiftUI
import MetalKit

/// SwiftUI entry point for the 3D viewer. Owns an `MTKView` + `MeshRenderer`
/// and translates drag/pinch gestures into `OrbitCamera` updates. Used both
/// for the offline Analysis viewer and as an overlay on top of the live AR
/// camera feed during scanning.
public struct MetalMeshView: UIViewRepresentable {
    @ObservedObject var controller: MeshViewController

    public init(controller: MeshViewController) {
        self.controller = controller
    }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = controller.renderer.device
        view.delegate = controller.renderer
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColorMake(0.04, 0.05, 0.07, 1.0) // matches dark industrial theme background
        view.isOpaque = controller.isOpaqueBackground
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false // continuous rendering; mesh + camera can change every frame

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        view.addGestureRecognizer(twoFingerPan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.isOpaque = controller.isOpaqueBackground
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    public final class Coordinator: NSObject {
        let controller: MeshViewController
        init(controller: MeshViewController) { self.controller = controller }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            controller.renderer.camera.rotate(
                deltaAzimuth: Float(translation.x) * -0.008,
                deltaElevation: Float(translation.y) * 0.008
            )
        }

        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            controller.renderer.camera.pan(deltaX: Float(translation.x), deltaY: Float(translation.y))
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            controller.renderer.camera.zoom(scale: Float(gesture.scale))
            gesture.scale = 1
        }
    }
}

/// Thin `ObservableObject` bridge so SwiftUI controls (opacity slider, style
/// picker, projection toggle) can drive the renderer without the view itself
/// needing to know about Metal.
@MainActor
public final class MeshViewController: ObservableObject {
    public let renderer: MeshRenderer
    public var isOpaqueBackground: Bool = true

    public init?(isOpaqueBackground: Bool = true) {
        guard let device = MTLCreateSystemDefaultDevice(), let renderer = MeshRenderer(device: device) else { return nil }
        self.renderer = renderer
        self.isOpaqueBackground = isOpaqueBackground
    }
}
