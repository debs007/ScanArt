import Metal
import MetalKit
import simd
import ScanArtAlgorithms

/// How the mesh should be shaded this frame.
public enum MeshDisplayMode: Sendable {
    /// Flat white/gray, opacity adjustable — the spec's "default rescan" state
    /// before a comparison has been run.
    case plain
    /// Per-vertex heat-map color from a `ThicknessColorMapper` result.
    case heatmap
}

public enum MeshRenderStyle: Sendable {
    case solid
    case wireframe
    case solidWithWireframeOverlay
}

/// GPU-side vertex layout. MUST match the Metal shader's `VertexIn` and the
/// `MTLVertexDescriptor` built in `MeshRenderer.makeVertexDescriptor()`.
struct GPUVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var color: SIMD4<Float>
}

struct Uniforms {
    var modelMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
    var lightDirection: SIMD3<Float>
    var opacity: Float
}

/// Owns the Metal pipeline and per-mesh GPU buffers. `MetalMeshView`
/// (the `UIViewRepresentable`) drives this as its `MTKViewDelegate`.
public final class MeshRenderer: NSObject {
    public var camera = OrbitCamera()
    public var displayMode: MeshDisplayMode = .plain
    public var renderStyle: MeshRenderStyle = .solid
    public var opacity: Float = 1.0
    public var plainColor: SIMD4<Float> = SIMD4<Float>(0.92, 0.93, 0.95, 1.0)

    /// Internal (module) access rather than `private` so `MetalMeshView` in this
    /// same module can hand the same device to `MTKView.device`.
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var solidPipeline: MTLRenderPipelineState?
    private var wireframePipeline: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?

    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0

    public init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()
        buildPipelines()
        buildDepthState()
    }

    // MARK: - Pipeline setup

    private func makeVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[2].format = .float4
        descriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        descriptor.attributes[2].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<GPUVertex>.stride
        return descriptor
    }

    private func buildPipelines() {
        let library = loadShaderLibrary()
        guard let library else {
            assertionFailure("ScanArtRendering: failed to load or compile the Metal shader library")
            return
        }
        let vertexFunction = library.makeFunction(name: "meshVertexShader")
        let solidFragment = library.makeFunction(name: "meshFragmentShader")
        let wireframeFragment = library.makeFunction(name: "wireframeFragmentShader")
        let vertexDescriptor = makeVertexDescriptor()

        func buildPipeline(fragment: MTLFunction?) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragment
            descriptor.vertexDescriptor = vertexDescriptor
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.depthAttachmentPixelFormat = .depth32Float
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        solidPipeline = buildPipeline(fragment: solidFragment)
        wireframePipeline = buildPipeline(fragment: wireframeFragment)
    }

    /// Tries the precompiled `default.metallib` embedded in this package's
    /// resource bundle first (the normal path for a `.metal` file declared
    /// via `.process()` in Package.swift). Falls back to compiling
    /// `EmbeddedShaderSource` from source at runtime if that's unavailable —
    /// see that file's doc comment for why this fallback exists.
    private func loadShaderLibrary() -> MTLLibrary? {
        if let precompiled = try? device.makeDefaultLibrary(bundle: .module) {
            return precompiled
        }
        return try? device.makeLibrary(source: EmbeddedShaderSource.metalLibrarySource, options: nil)
    }

    private func buildDepthState() {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: descriptor)
    }

    // MARK: - Content upload

    /// Uploads plain-shaded geometry (no thickness data yet — the spec's
    /// "default rescan: white mesh" state).
    public func setMesh(_ mesh: MeshBuffer) {
        let vertices = (0..<mesh.vertexCount).map {
            GPUVertex(position: mesh.vertices[$0], normal: mesh.normals[$0], color: plainColor)
        }
        upload(vertices: vertices, indices: mesh.indices)
    }

    /// Uploads heat-map colored geometry from a completed thickness comparison.
    /// `samples` must be parallel to `original.vertices` (i.e. produced by
    /// `ThicknessCalculator.compute(original: original, ...)`).
    public func setHeatmapMesh(original: MeshBuffer, samples: [ThicknessSample], colorMapper: ThicknessColorMapper) {
        var vertices: [GPUVertex] = []
        vertices.reserveCapacity(original.vertexCount)
        for i in 0..<original.vertexCount {
            let sample = i < samples.count ? samples[i] : nil
            let color: SIMD4<Float>
            if let sample, sample.isValid {
                let c = colorMapper.color(for: Double(sample.thicknessMM))
                color = SIMD4<Float>(Float(c.r), Float(c.g), Float(c.b), Float(c.a))
            } else {
                let c = ThicknessColorMapper.noData
                color = SIMD4<Float>(Float(c.r), Float(c.g), Float(c.b), Float(c.a))
            }
            vertices.append(GPUVertex(position: original.vertices[i], normal: original.normals[i], color: color))
        }
        upload(vertices: vertices, indices: original.indices)
    }

    private func upload(vertices: [GPUVertex], indices: [UInt32]) {
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<GPUVertex>.stride, options: .storageModeShared)
        indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        indexCount = indices.count
    }
}

extension MeshRenderer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let vertexBuffer, let indexBuffer, indexCount > 0,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        let aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
        var uniforms = Uniforms(
            modelMatrix: .identity,
            viewMatrix: camera.viewMatrix(),
            projectionMatrix: camera.projectionMatrix(aspect: aspect),
            lightDirection: normalize(SIMD3<Float>(-0.4, -1.0, -0.3)),
            opacity: opacity
        )

        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        if renderStyle != .wireframe, let solidPipeline {
            encoder.setRenderPipelineState(solidPipeline)
            encoder.setTriangleFillMode(.fill)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
        }

        if renderStyle != .solid, let wireframePipeline {
            encoder.setRenderPipelineState(wireframePipeline)
            encoder.setTriangleFillMode(.lines)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
