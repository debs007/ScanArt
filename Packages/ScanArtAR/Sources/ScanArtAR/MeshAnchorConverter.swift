import ARKit
import simd
import ScanArtAlgorithms

/// Converts the raw GPU buffers ARKit hands back for a set of `ARMeshAnchor`s
/// into a single world-space `MeshBuffer`. This is the ONLY place in the app
/// that touches `ARMeshGeometry`'s buffer layout — everything downstream
/// (algorithms, rendering, export) works with the framework-agnostic type.
public enum MeshAnchorConverter {

    public static func convert(_ anchors: [ARMeshAnchor]) -> MeshBuffer {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var faceClassifications: [MeshRegionClass] = []

        for anchor in anchors {
            let transform = anchor.transform
            let geometry = anchor.geometry
            let vertexOffset = vertices.count

            appendVertices(from: geometry.vertices, transformedBy: transform, into: &vertices)
            appendNormals(from: geometry.normals, transformedBy: transform, into: &normals)
            appendFaces(from: geometry.faces, vertexOffset: UInt32(vertexOffset), into: &indices)

            if let classificationSource = geometry.classification {
                appendClassifications(from: classificationSource, faceCount: geometry.faces.count, into: &faceClassifications)
            }
        }

        // If only SOME anchors had classification data (shouldn't normally
        // happen within one session, but guards against a partial capture),
        // drop classification entirely rather than mis-align it with faces.
        let expectedFaceCount = indices.count / 3
        let safeClassifications = faceClassifications.count == expectedFaceCount ? faceClassifications : []

        return MeshBuffer(vertices: vertices, normals: normals, indices: indices, faceClassifications: safeClassifications)
    }

    private static func appendVertices(from source: ARGeometrySource, transformedBy transform: simd_float4x4, into vertices: inout [SIMD3<Float>]) {
        let pointer = source.buffer.contents().advanced(by: source.offset)
        for i in 0..<source.count {
            let raw = pointer.advanced(by: i * source.stride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            vertices.append(transform.transformPoint(raw))
        }
    }

    private static func appendNormals(from source: ARGeometrySource, transformedBy transform: simd_float4x4, into normals: inout [SIMD3<Float>]) {
        let pointer = source.buffer.contents().advanced(by: source.offset)
        for i in 0..<source.count {
            let raw = pointer.advanced(by: i * source.stride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            normals.append(normalize(transform.transformDirection(raw)))
        }
    }

    private static func appendFaces(from element: ARGeometryElement, vertexOffset: UInt32, into indices: inout [UInt32]) {
        let pointer = element.buffer.contents()
        let indicesPerFace = element.indexCountPerPrimitive // 3 for triangles
        let bytesPerIndex = element.bytesPerIndex

        for face in 0..<element.count {
            for corner in 0..<indicesPerFace {
                let byteOffset = (face * indicesPerFace + corner) * bytesPerIndex
                let localIndex: UInt32
                if bytesPerIndex == 2 {
                    localIndex = UInt32(pointer.advanced(by: byteOffset).assumingMemoryBound(to: UInt16.self).pointee)
                } else {
                    localIndex = pointer.advanced(by: byteOffset).assumingMemoryBound(to: UInt32.self).pointee
                }
                indices.append(vertexOffset + localIndex)
            }
        }
    }

    private static func appendClassifications(from source: ARGeometrySource, faceCount: Int, into classifications: inout [MeshRegionClass]) {
        let pointer = source.buffer.contents().advanced(by: source.offset)
        for i in 0..<faceCount {
            let raw = pointer.advanced(by: i * source.stride).assumingMemoryBound(to: ARMeshClassification.self).pointee
            classifications.append(MeshRegionClass(arMeshClassification: raw))
        }
    }
}

extension MeshRegionClass {
    init(arMeshClassification: ARMeshClassification) {
        switch arMeshClassification {
        case .wall: self = .wall
        case .floor: self = .floor
        case .ceiling: self = .ceiling
        case .table: self = .table
        case .seat: self = .seat
        case .window: self = .window
        case .door: self = .door
        case .none: self = .unknown
        @unknown default: self = .unknown
        }
    }
}
