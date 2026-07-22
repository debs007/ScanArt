import Foundation
import Compression
import ScanArtAlgorithms

/// The app's own compact binary format for locally-stored mesh/sample data —
/// distinct from the interchange formats in ScanArtExport (DXF/OBJ/PLY/...).
/// This format optimizes for fast round-trip and small on-disk size, not for
/// opening in other software.
///
/// Layout (all little-endian):
///   magic:     4 bytes  "SAMB"
///   version:   UInt32
///   vertexCount: UInt32
///   faceCount:   UInt32          (indices.count / 3)
///   hasClassification: UInt8
///   [vertices]   vertexCount * 3 * Float32
///   [normals]    vertexCount * 3 * Float32
///   [indices]    faceCount * 3 * UInt32
///   [classifications] faceCount * UInt8   (only if hasClassification)
///
/// The whole payload (after the magic+version) is LZFSE-compressed via
/// `Compression` — LZFSE is Apple's own algorithm, tuned for exactly this
/// kind of on-device, same-ecosystem round trip (fast decode, no cross-platform
/// requirement here since this file never leaves the app).
public enum MeshFileStorage {
    private static let magic: [UInt8] = Array("SAMB".utf8)
    private static let version: UInt32 = 1

    public static func save(_ mesh: MeshBuffer, to url: URL) throws {
        var payload = Data()
        payload.append(contentsOf: le(UInt32(mesh.vertexCount)))
        payload.append(contentsOf: le(UInt32(mesh.faceCount)))
        payload.append(mesh.faceClassifications.isEmpty ? 0 : 1)

        for v in mesh.vertices { payload.append(contentsOf: le(v.x)); payload.append(contentsOf: le(v.y)); payload.append(contentsOf: le(v.z)) }
        for n in mesh.normals { payload.append(contentsOf: le(n.x)); payload.append(contentsOf: le(n.y)); payload.append(contentsOf: le(n.z)) }
        for i in mesh.indices { payload.append(contentsOf: le(i)) }
        if !mesh.faceClassifications.isEmpty {
            payload.append(contentsOf: mesh.faceClassifications.map(\.rawValue))
        }

        try write(magic: magic, payload: payload, to: url)
    }

    public static func loadMesh(from url: URL) throws -> MeshBuffer {
        let payload = try readPayload(from: url, expectedMagic: magic)
        var offset = 0
        let vertexCount = Int(readUInt32(payload, &offset))
        let faceCount = Int(readUInt32(payload, &offset))
        let hasClassification = payload[payload.startIndex + offset] == 1
        offset += 1

        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            vertices.append(SIMD3<Float>(readFloat(payload, &offset), readFloat(payload, &offset), readFloat(payload, &offset)))
        }
        var normals: [SIMD3<Float>] = []
        normals.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            normals.append(SIMD3<Float>(readFloat(payload, &offset), readFloat(payload, &offset), readFloat(payload, &offset)))
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(faceCount * 3)
        for _ in 0..<(faceCount * 3) {
            indices.append(readUInt32(payload, &offset))
        }
        var classifications: [MeshRegionClass] = []
        if hasClassification {
            classifications.reserveCapacity(faceCount)
            for _ in 0..<faceCount {
                let raw = payload[payload.startIndex + offset]
                offset += 1
                classifications.append(MeshRegionClass(rawValue: raw) ?? .unknown)
            }
        }
        return MeshBuffer(vertices: vertices, normals: normals, indices: indices, faceClassifications: classifications)
    }

    // MARK: - Thickness samples

    private static let samplesMagic: [UInt8] = Array("SATS".utf8) // Scan Art Thickness Samples

    public static func saveSamples(_ samples: [ThicknessSample], to url: URL) throws {
        var payload = Data()
        payload.append(contentsOf: le(UInt32(samples.count)))
        for s in samples {
            payload.append(contentsOf: le(s.position.x)); payload.append(contentsOf: le(s.position.y)); payload.append(contentsOf: le(s.position.z))
            payload.append(contentsOf: le(s.normal.x)); payload.append(contentsOf: le(s.normal.y)); payload.append(contentsOf: le(s.normal.z))
            payload.append(contentsOf: le(s.thicknessMM))
            payload.append(s.isValid ? 1 : 0)
        }
        try write(magic: samplesMagic, payload: payload, to: url)
    }

    public static func loadSamples(from url: URL) throws -> [ThicknessSample] {
        let payload = try readPayload(from: url, expectedMagic: samplesMagic)
        var offset = 0
        let count = Int(readUInt32(payload, &offset))
        var samples: [ThicknessSample] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            let position = SIMD3<Float>(readFloat(payload, &offset), readFloat(payload, &offset), readFloat(payload, &offset))
            let normal = SIMD3<Float>(readFloat(payload, &offset), readFloat(payload, &offset), readFloat(payload, &offset))
            let thickness = readFloat(payload, &offset)
            let isValid = payload[payload.startIndex + offset] == 1
            offset += 1
            samples.append(ThicknessSample(position: position, normal: normal, thicknessMM: thickness, isValid: isValid))
        }
        return samples
    }

    // MARK: - Compression + framing shared by both formats

    private static func write(magic: [UInt8], payload: Data, to url: URL) throws {
        guard let compressed = compress(payload) else {
            throw MeshStorageError.compressionFailed
        }
        var file = Data(magic)
        file.append(contentsOf: le(version))
        file.append(compressed)
        try file.write(to: url, options: .atomic)
    }

    private static func readPayload(from url: URL, expectedMagic: [UInt8]) throws -> Data {
        let file = try Data(contentsOf: url)
        guard file.count > 8, Array(file.prefix(4)) == expectedMagic else {
            throw MeshStorageError.badFormat
        }
        let compressed = file.suffix(from: file.startIndex + 8)
        guard let decompressed = decompress(Data(compressed)) else {
            throw MeshStorageError.decompressionFailed
        }
        return decompressed
    }

    private static func compress(_ data: Data) -> Data? {
        try? (data as NSData).compressed(using: .lzfse) as Data
    }

    private static func decompress(_ data: Data) -> Data? {
        try? (data as NSData).decompressed(using: .lzfse) as Data
    }

    // MARK: - Little-endian primitives

    private static func le(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
    private static func le(_ v: Float) -> [UInt8] { withUnsafeBytes(of: v.bitPattern.littleEndian) { Array($0) } }

    private static func readUInt32(_ data: Data, _ offset: inout Int) -> UInt32 {
        let start = data.startIndex + offset
        let bytes = data[start..<start + 4]
        offset += 4
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    private static func readFloat(_ data: Data, _ offset: inout Int) -> Float {
        let bits = readUInt32(data, &offset)
        return Float(bitPattern: bits)
    }
}

public enum MeshStorageError: Error, LocalizedError {
    case compressionFailed, decompressionFailed, badFormat
    public var errorDescription: String? {
        switch self {
        case .compressionFailed: return "Failed to compress mesh data."
        case .decompressionFailed: return "Failed to decompress mesh data — the file may be corrupt."
        case .badFormat: return "Unrecognized mesh file format."
        }
    }
}
