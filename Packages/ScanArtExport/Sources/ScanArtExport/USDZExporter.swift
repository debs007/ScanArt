import Foundation
import ModelIO
import ScanArtAlgorithms

/// USDZ export via Model I/O rather than hand-rolled: USDZ is a zipped USD
/// Crate binary format, and Apple's own encoder (which `MDLAsset.export`
/// drives) is the correct tool for it rather than reimplementing that binary
/// format by hand.
///
/// Scope note: this exports geometry (position + normal) faithfully, without
/// the heat-map baked in as per-vertex color — Model I/O's material model
/// is texture/PBR-oriented rather than exposing a simple per-vertex-color
/// channel the way PLY does. If you need the colored mesh outside the app,
/// use PLY (full color) or DXF (color via CAD layers); USDZ here is meant for
/// geometry interchange and AR Quick Look preview. Baking a vertex-color
/// texture into the USDZ material is tracked as a Phase 2 enhancement in
/// ROADMAP.md.
public enum USDZExporter: MeshExporter {
    public static func export(_ payload: ExportPayload, to url: URL) throws {
        let mesh = payload.mesh
        guard mesh.vertexCount > 0, mesh.faceCount > 0 else {
            throw ExportError.missingData("Mesh has no geometry to export")
        }

        let allocator = MDLMeshBufferDataAllocator()

        var positions: [Float] = []
        var normals: [Float] = []
        positions.reserveCapacity(mesh.vertexCount * 3)
        normals.reserveCapacity(mesh.vertexCount * 3)
        for i in 0..<mesh.vertexCount {
            positions.append(contentsOf: [mesh.vertices[i].x, mesh.vertices[i].y, mesh.vertices[i].z])
            normals.append(contentsOf: [mesh.normals[i].x, mesh.normals[i].y, mesh.normals[i].z])
        }

        let positionData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let normalData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let positionBuffer = allocator.newBuffer(with: positionData, type: .vertex)
        let normalBuffer = allocator.newBuffer(with: normalData, type: .vertex)

        let indexData = mesh.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 0, bufferIndex: 1)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.stride * 3)
        vertexDescriptor.layouts[1] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.stride * 3)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: mesh.indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        let mdlMesh = MDLMesh(
            vertexBuffers: [positionBuffer, normalBuffer],
            vertexCount: mesh.vertexCount,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )
        mdlMesh.name = payload.scanLabel.isEmpty ? "ScanArtMesh" : payload.scanLabel

        let asset = MDLAsset()
        asset.add(mdlMesh)

        // Remove any stale file first — MDLAsset.export throws if the
        // destination already exists.
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try asset.export(to: url)
    }
}
