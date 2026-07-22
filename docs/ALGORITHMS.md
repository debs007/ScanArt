# Algorithms

All implementations referenced here live in `Packages/ScanArtAlgorithms/Sources/ScanArtAlgorithms/`.

## Alignment

### Primary: ARWorldMap relocalization

Not an algorithm implemented in this codebase so much as a capture-time decision — see `ARCHITECTURE.md`'s "Alignment strategy" section and `ARScanSessionManager.swift`. Both scans are placed in the same coordinate frame by ARKit's own visual-inertial tracking, using the original scan's saved `ARWorldMap`.

### Refinement: ICP with Horn's closed-form rotation

`Alignment/ICPAligner.swift`. Standard iterative closest point, with one specific numerical method chosen deliberately:

At each iteration, once point correspondences are found (nearest-neighbor search via `SpatialHashGrid`, with correspondences beyond `maxCorrespondenceDistance` discarded and the remainder trimmed by a robust outlier threshold — correspondences farther than `outlierMultiplier × median distance` are rejected before solving), the best-fit rigid rotation between the two correspondence point sets is solved using **Horn's 1987 closed-form quaternion method**:

1. Compute the cross-covariance matrix of the (mean-centered) correspondence sets.
2. Build the 4×4 symmetric matrix `N` from that covariance matrix's components (Horn's construction).
3. The optimal rotation quaternion is `N`'s eigenvector corresponding to its largest eigenvalue.
4. Find that eigenvector via Gershgorin-circle-shifted power iteration (shifting `N` by an upper bound on its eigenvalue magnitude, from the Gershgorin circle theorem, guarantees the power iteration converges to the *largest* eigenvalue rather than whichever has largest magnitude).

This was chosen over the more common "3×3 SVD of the cross-covariance matrix" approach specifically because Apple's Accelerate framework doesn't expose a general SVD as a simple one-call API, and hand-rolling a numerically stable general SVD was a much larger risk surface than implementing Horn's method, which only needs eigen-decomposition of a single symmetric 4×4 matrix. Translation is then solved in closed form from the rotation and the two centroids. Scale is never solved for — the spec explicitly disables it, and a measurement tool that could silently rescale one of the two walls being compared would actively corrupt every downstream measurement.

Convergence: iterate until RMSE change between iterations drops below `convergenceThreshold`, or `maxIterations` is hit. The result (`AlignmentResult`) reports RMSE, iteration count, correspondence count, and whether it converged — surfaced to the user as alignment quality (`ScanRecord.alignmentRMSEMM`).

## Thickness calculation

`Comparison/ThicknessCalculator.swift`. For each point on the *original* (pre-plaster) wall surface, thickness is "how far did the surface move outward here?" — measured along that point's original surface normal.

Two methods:
- **`.nearestNeighborProjection`** — find the nearest vertex on the rescan mesh (via `SpatialHashGrid`), then project the displacement onto the original point's normal. O(n), used for fast live-preview scenarios.
- **`.rayMeshIntersection`** — cast a ray from the original point along its normal (tried in both directions, to tolerate small alignment sign noise) into the rescan mesh, using standard Möller–Trumbore ray-triangle intersection, accelerated by `TriangleSpatialHashGrid` (buckets candidate triangles by centroid so the ray only tests nearby geometry). This is what "Generate thickness map" uses — slower, but not biased by uneven rescan vertex density the way nearest-vertex projection can be on rough or lumpy plaster.

Both methods cap search distance (`maxSearchDistance`) so a hole in the rescan mesh is correctly marked invalid rather than reporting a spurious multi-meter "thickness." Work is chunked across `original`'s vertices and fanned out over a `TaskGroup` (~8-way parallelism) since this is the single most expensive step in the pipeline for a room-scale mesh.

## Surface area and volume

`Comparison/SurfaceAreaCalculator.swift`, `Comparison/VolumeCalculator.swift`.

- **Surface area**: sum of triangle areas via the standard cross-product formula, `0.5 * |cross(b-a, c-a)|`.
- **Per-vertex area of influence**: each triangle contributes 1/3 of its area to each of its three corner vertices — the standard barycentric weighting used to turn a per-vertex scalar quantity into a surface integral.
- **Volume** = Σ (thickness at vertex `i` × area of influence at vertex `i`), summed only over valid samples. This is a discrete approximation of integrating thickness across the wall surface, accurate as long as sample density is reasonably uniform — true for LiDAR scene-reconstruction meshes, which are close to uniform-density by construction. Negative thickness (a spot where the surface receded rather than grew — possible at scan noise or edges) subtracts from the running total rather than being clamped to zero per-sample, but the final total is clamped at zero.

## Statistics

`Statistics/ThicknessStatistics.swift`. Mean, min, max, median, and **sample** standard deviation (n−1 denominator — the conventional choice when treating the measured points as a sample of a larger population rather than the entire population) over valid samples only. "Within tolerance" is the fraction of valid samples inside `[desired − tolerance, desired + tolerance]`. Histogram binning is linear across the observed min–max range.

## Color mapping

`ColorMapping/ThicknessColorMapper.swift`. Piecewise-linear interpolation between an ascending list of `ColorStop`s. The standard 7-band palette (`standard(desiredThicknessMM:toleranceMM:)`) is built relative to the project's desired thickness and tolerance — "on target" is always centered exactly on the desired value, regardless of what that value is. Invalid/no-data samples (holes in the rescan, or points where neither ray direction hit anything within search range) render as a distinct neutral gray rather than being silently omitted or confused with "very thin," which matters for the same reason `ThicknessSample.isValid` exists at all: a missing measurement and a bad measurement are different facts, and collapsing them would hide real data-quality problems from the person reading the heat map.

## Mesh decimation

`Geometry/MeshDecimator.swift`. Grid-based vertex clustering (partition space into voxels, collapse every vertex in a voxel to a running-average centroid, remap faces, drop any face that degenerates when two or more corners collapse together). This is the same family of technique as MeshLab's "Clustering Decimation" — simpler than quadric-error-metric (QEM) decimation, which preserves fine detail much better at aggressive reduction ratios, but implementable correctly without a compiler in the loop to check the math against. A QEM-based decimator is a Phase 2 item (see `ROADMAP.md`) if very large scans need higher decimation ratios without visible loss of wall detail.
