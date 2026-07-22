import simd

/// Result of an alignment pass.
public struct AlignmentResult: Sendable {
    /// Rigid transform (rotation + translation, NO scale) that maps the source
    /// mesh onto the target mesh's coordinate frame.
    public let transform: simd_float4x4
    /// RMS distance (meters) between corresponding points after alignment —
    /// the alignment quality readout the spec asks to surface to the user.
    public let rmse: Float
    public let iterationsRun: Int
    public let correspondenceCount: Int
    public let converged: Bool
}

/// Iterative Closest Point alignment, using Horn's 1987 closed-form quaternion
/// solution for the rotation at each iteration (rather than a general 3x3 SVD,
/// which Swift/Accelerate doesn't hand you directly). Scaling is never solved
/// for — the spec explicitly disables it, and a measurement tool that could
/// silently rescale one of the two walls being compared would be actively
/// dangerous.
///
/// IMPORTANT DOMAIN NOTE — read before changing this file:
/// Running plain ICP on the *whole* pre/post-plaster meshes is wrong. ICP's
/// objective is to minimize point-to-point distance, but the wall surface is
/// EXPECTED to have moved outward by the plaster thickness — that offset is
/// the signal we're trying to measure, not noise to align away. Unconstrained
/// ICP will happily converge to a transform that slides the new wall back onto
/// the old one, deflating every thickness reading toward zero.
///
/// The app's primary alignment path is therefore `ARWorldMap` relocalization
/// (see ScanArtAR.ARScanSessionManager), which puts both scans in the same
/// real-world coordinate frame using ARKit's own visual-inertial tracking —
/// no geometric alignment needed at all. `ICPAligner` exists as a *refinement*
/// step for residual drift, and callers MUST restrict its input to
/// `MeshRegionClass.isStableReference` faces (floor/ceiling/window/door) via
/// `MeshBuffer.filteredByFace`, never the wall being measured.
public enum ICPAligner {

    public struct Configuration: Sendable {
        public var maxIterations: Int = 40
        public var convergenceThreshold: Float = 1e-5 // meters, change in RMSE between iterations
        /// Correspondences farther than `outlierMultiplier` x median distance are
        /// rejected before solving each iteration (robust trimming).
        public var outlierMultiplier: Float = 2.5
        /// Nearest-neighbor search cutoff, meters. Correspondences beyond this are
        /// never considered even before outlier rejection.
        public var maxCorrespondenceDistance: Float = 0.5
        /// Spatial hash cell size, meters. ~2x the LiDAR mesh's typical vertex
        /// spacing (a few cm) is a good default.
        public var cellSize: Float = 0.05

        public init() {}
    }

    /// Aligns `source` onto `target`. Both should already be restricted to stable
    /// reference geometry by the caller (see note above).
    public static func align(
        source: MeshBuffer,
        target: MeshBuffer,
        initialTransform: simd_float4x4 = .identity,
        configuration: Configuration = Configuration()
    ) -> AlignmentResult {
        guard !source.vertices.isEmpty, !target.vertices.isEmpty else {
            return AlignmentResult(transform: initialTransform, rmse: .greatestFiniteMagnitude, iterationsRun: 0, correspondenceCount: 0, converged: false)
        }

        let targetGrid = SpatialHashGrid(points: target.vertices, cellSize: configuration.cellSize)
        var currentTransform = initialTransform
        var previousRMSE: Float = .greatestFiniteMagnitude
        var lastCorrespondenceCount = 0
        var converged = false
        var iterationsRun = 0

        for iteration in 0..<configuration.maxIterations {
            iterationsRun = iteration + 1
            let transformedSource = source.vertices.map(currentTransform.transformPoint)

            // 1. Find correspondences.
            var sourcePts: [SIMD3<Float>] = []
            var targetPts: [SIMD3<Float>] = []
            var distances: [Float] = []
            sourcePts.reserveCapacity(transformedSource.count)
            targetPts.reserveCapacity(transformedSource.count)

            for p in transformedSource {
                guard let match = targetGrid.nearestNeighbor(to: p, maxRadius: configuration.maxCorrespondenceDistance) else { continue }
                sourcePts.append(p)
                targetPts.append(target.vertices[Int(match.index)])
                distances.append(sqrt(match.distanceSquared))
            }

            guard sourcePts.count >= 6 else {
                // Not enough stable-reference overlap to trust a refinement — bail
                // out and let the caller fall back to relocalization-only alignment.
                return AlignmentResult(transform: currentTransform, rmse: previousRMSE, iterationsRun: iterationsRun, correspondenceCount: sourcePts.count, converged: false)
            }

            // 2. Robust outlier rejection via median distance.
            let sortedDistances = distances.sorted()
            let median = sortedDistances[sortedDistances.count / 2]
            let threshold = max(median * configuration.outlierMultiplier, 1e-4)
            var filteredSource: [SIMD3<Float>] = []
            var filteredTarget: [SIMD3<Float>] = []
            for i in 0..<sourcePts.count where distances[i] <= threshold {
                filteredSource.append(sourcePts[i])
                filteredTarget.append(targetPts[i])
            }
            guard filteredSource.count >= 6 else {
                return AlignmentResult(transform: currentTransform, rmse: previousRMSE, iterationsRun: iterationsRun, correspondenceCount: filteredSource.count, converged: false)
            }
            lastCorrespondenceCount = filteredSource.count

            // 3. Solve the incremental rigid transform via Horn's method and compose it.
            let delta = HornAbsoluteOrientation.solve(source: filteredSource, target: filteredTarget)
            currentTransform = delta * currentTransform

            // 4. RMSE for convergence check + user-facing quality readout.
            var sumSq: Float = 0
            for i in 0..<filteredSource.count {
                let moved = delta.transformPoint(filteredSource[i])
                sumSq += simd_length_squared(moved - filteredTarget[i])
            }
            let rmse = sqrt(sumSq / Float(filteredSource.count))

            if abs(previousRMSE - rmse) < configuration.convergenceThreshold {
                previousRMSE = rmse
                converged = true
                break
            }
            previousRMSE = rmse
        }

        return AlignmentResult(
            transform: currentTransform,
            rmse: previousRMSE,
            iterationsRun: iterationsRun,
            correspondenceCount: lastCorrespondenceCount,
            converged: converged
        )
    }
}

/// Horn's 1987 closed-form solution to the "absolute orientation" problem:
/// given paired points, find the rotation + translation (no scale) minimizing
/// sum of squared distances. This avoids needing a general 3x3 SVD (which
/// Accelerate doesn't expose as a one-liner) by reducing rotation estimation
/// to finding the dominant eigenvector of a 4x4 symmetric matrix, which power
/// iteration handles reliably.
enum HornAbsoluteOrientation {
    static func solve(source: [SIMD3<Float>], target: [SIMD3<Float>]) -> simd_float4x4 {
        precondition(source.count == target.count && !source.isEmpty)
        let n = Float(source.count)

        let sourceCentroid = source.reduce(SIMD3<Float>.zero, +) / n
        let targetCentroid = target.reduce(SIMD3<Float>.zero, +) / n

        // Cross-covariance matrix M[i][j] = sum(source'.i * target'.j)
        var sxx: Float = 0, sxy: Float = 0, sxz: Float = 0
        var syx: Float = 0, syy: Float = 0, syz: Float = 0
        var szx: Float = 0, szy: Float = 0, szz: Float = 0
        for i in 0..<source.count {
            let s = source[i] - sourceCentroid
            let t = target[i] - targetCentroid
            sxx += s.x * t.x; sxy += s.x * t.y; sxz += s.x * t.z
            syx += s.y * t.x; syy += s.y * t.y; syz += s.y * t.z
            szx += s.z * t.x; szy += s.z * t.y; szz += s.z * t.z
        }

        // Horn's 4x4 symmetric N matrix built from the cross-covariance terms.
        // The unit quaternion (w, x, y, z) maximizing q^T N q — i.e. the eigenvector
        // of N's LARGEST eigenvalue — is the optimal rotation.
        let n00 = sxx + syy + szz
        let n01 = syz - szy
        let n02 = szx - sxz
        let n03 = sxy - syx
        let n11 = sxx - syy - szz
        let n12 = sxy + syx
        let n13 = szx + sxz
        let n22 = -sxx + syy - szz
        let n23 = syz + szy
        let n33 = -sxx - syy + szz

        let N: [[Float]] = [
            [n00, n01, n02, n03],
            [n01, n11, n12, n13],
            [n02, n12, n22, n23],
            [n03, n13, n23, n33]
        ]

        let q = dominantEigenvector(ofSymmetric4x4: N)
        let rotation = quaternionToMatrix(w: q[0], x: q[1], y: q[2], z: q[3])
        let translation = targetCentroid - rotation.transformDirection(sourceCentroid)

        var result = rotation
        result.columns.3 = SIMD4<Float>(translation, 1)
        return result
    }

    /// Power iteration on a Gershgorin-shifted copy of `N`. Plain power iteration
    /// converges to the eigenvalue of largest MAGNITUDE, which for an indefinite
    /// matrix like N isn't necessarily the largest (most positive) one we need.
    /// Shifting by the Gershgorin bound (sum of |row|) makes every eigenvalue of
    /// the shifted matrix positive while preserving their relative order, so power
    /// iteration on the shifted matrix reliably finds the eigenvector we actually want.
    private static func dominantEigenvector(ofSymmetric4x4 matrix: [[Float]]) -> [Float] {
        let shift = (0..<4).map { i in (0..<4).reduce(Float(0)) { $0 + abs(matrix[i][$1]) } }.max() ?? 0

        var v: [Float] = [1, 0, 0, 0]
        for _ in 0..<200 {
            var next = [Float](repeating: 0, count: 4)
            for i in 0..<4 {
                var sum: Float = shift * v[i] // contribution of the +shift*I term
                for j in 0..<4 { sum += matrix[i][j] * v[j] }
                next[i] = sum
            }
            let norm = sqrt(next.reduce(0) { $0 + $1 * $1 })
            guard norm > 1e-12 else { break }
            next = next.map { $0 / norm }
            let delta = zip(next, v).reduce(Float(0)) { $0 + abs($1.0 - $1.1) }
            v = next
            if delta < 1e-9 { break }
        }
        // Normalize sign so w >= 0 (quaternion q and -q represent the same rotation;
        // this just keeps results deterministic/comparable across calls).
        if v[0] < 0 { v = v.map { -$0 } }
        return v
    }

    private static func quaternionToMatrix(w: Float, x: Float, y: Float, z: Float) -> simd_float4x4 {
        let xx = x * x, yy = y * y, zz = z * z
        let xy = x * y, xz = x * z, yz = y * z
        let wx = w * x, wy = w * y, wz = w * z
        return simd_float4x4(columns: (
            SIMD4<Float>(1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0),
            SIMD4<Float>(2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0),
            SIMD4<Float>(2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
}
