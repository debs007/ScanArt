# Database & Storage Schema

Scan Art splits storage into two tiers: **SwiftData** for lightweight, queryable metadata, and **flat files on disk** for heavy binary data (meshes, thickness samples, world maps). This split is what keeps the project list, timeline, and search fast — none of those views ever load megabytes of mesh geometry just to show a list of names and dates.

All physical measurements stored anywhere in SwiftData are in **millimeters**, regardless of a project's display unit — `MeasurementUnit` only affects UI formatting (`ScanArtCore/Models/Enums.swift`).

## SwiftData models

Full field-level definitions live in `Packages/ScanArtCore/Sources/ScanArtCore/Models/`. Summary:

### `Project`
The top-level entity a user creates: one wall (or set of walls) tracked from its original scan through any number of rescans. Holds identification fields (name, customer, engineer, site/building/room/floor), the target measurement (`desiredThicknessMM`, `toleranceMM`, `unitRawValue`), and cascade-delete relationships to `scans: [ScanRecord]` and `reports: [ReportRecord]`. `isLocked` is reserved for the Phase 2 Face ID/passcode project lock (see `ROADMAP.md`) — the field exists now so it round-trips through future sync/export without a schema migration later.

### `ScanRecord`
One capture — either the original (pre-plaster) scan or a rescan. `scanTypeRawValue` distinguishes them; `sequenceNumber` is 0 for the original, 1/2/3… for rescans in capture order. Stores mesh *metadata* (vertex/face count, surface area, bounding box, file size) and a `meshFileName` pointing at the actual geometry on disk. `worldMapFileName` points at the archived `ARWorldMap`, when captured, used for relocalizing the *next* rescan. `alignmentTransform`/`alignmentRMSEMM`/`relocalizationSucceeded` are nil for the original scan (which defines the coordinate frame) and populated for rescans once alignment runs. Cascade-deletes its `thicknessResults`.

### `ThicknessResult`
The output of comparing two scans. `comparedAgainstScanID` names the *other* scan (usually the original, but the model allows any pair — see `ARCHITECTURE.md`'s note on Phase 1 UI scope). Aggregate statistics (average/min/max/median/stddev/tolerance %/volume) are stored directly as attributes for fast display; `samplesFileName` points at the full per-vertex sample array on disk. A single `ScanRecord` can have multiple `ThicknessResult`s if compared against different baselines.

### `ReportRecord`
Metadata for a generated PDF report — title, `pdfFileName`, generation date, which scans it covers (`includedScanIDs`), and a snapshot of engineer/customer name at generation time (so a later name change doesn't retroactively alter historical reports).

## On-disk layout

```
Application Support/ScanArt/Projects/<project-uuid>/
  Meshes/
    <scan-uuid>.scanmesh      Compressed binary mesh (see below)
    <scan-uuid>.worldmap      Archived ARWorldMap (NSKeyedArchiver, NSSecureCoding)
  Thickness/
    <result-uuid>_samples.bin Compressed binary per-vertex thickness samples
  Reports/
    <report-uuid-prefix>.pdf
  Exports/
    *.dxf / *.obj / *.ply / *.stl / *.usdz / *.csv / *.json
  Images/
    (reserved for user-captured reference photos)
```

`Application Support` rather than `Documents` is deliberate: this is app-managed data, not meant to be user-browsable via the Files app — matching the spec's local/offline/lockable posture. Exports are handed to the user explicitly via a share sheet at the moment of export, which is the appropriate way to get a file out of the sandbox.

### `.scanmesh` / `_samples.bin` binary format

Implemented in `ScanArtPersistence/MeshFileStorage.swift`. This is the app's own compact internal format — distinct from the interchange formats in `ScanArtExport` (DXF/OBJ/PLY/…), which optimize for compatibility with other software rather than round-trip speed.

```
magic:      4 bytes ("SAMB" for meshes, "SATS" for thickness samples)
version:    UInt32
[LZFSE-compressed payload]
```

The mesh payload (post-decompression): vertex count, face count, a classification-present flag, then the vertex positions, vertex normals, triangle indices, and (if present) per-face classification bytes, all little-endian. The samples payload: sample count, then position/normal/thickness/validity per sample.

LZFSE (via the `Compression` framework) was chosen because it's Apple's own algorithm, tuned for exactly this kind of same-ecosystem, on-device round trip (fast decode, no cross-platform requirement — this file never leaves the app).

## Why metadata and geometry are split at all

Two consequences of storing mesh/sample data as files rather than as SwiftData `Data` blobs, both intentional:
1. The project list, search, and timeline screens only ever fetch small rows — no risk of a list view momentarily loading tens of megabytes of geometry it doesn't display.
2. Repository protocols stay `@MainActor`-safe without needing SwiftData to ever hand a huge blob across an actor boundary — file I/O for the heavy data happens through plain `Sendable` types (`MeshBuffer`, `[ThicknessSample]`, `URL`) that can freely move to a background `Task.detached`, exactly the concurrency split described in `ARCHITECTURE.md`.
