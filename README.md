# Scan Art

LiDAR-based plaster thickness measurement for civil engineers, architects, and contractors. Scan a bare wall before plastering, rescan it after, and Scan Art aligns the two scans and computes a colored thickness map, statistics, volume, and exportable reports — entirely offline, on-device.

## Status

This is a genuine, from-scratch implementation of Phase 1: every algorithm, screen, and export format described below is fully implemented Swift code, not a stub or mockup. It has **not been compiled or run** — this was built in an environment without Xcode/macOS/a Swift compiler available, so there has been no build-and-fix pass. Treat the first `xcodegen generate` + build in Xcode as the real start of verification, not a formality. See **"Known risk areas"** below for the specific spots most likely to need a fix, and `docs/ROADMAP.md` for what's deliberately out of scope for Phase 1.

## Requirements

- Xcode 16 or later, on macOS
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A physical iPhone or iPad with a LiDAR Scanner (iPhone 12 Pro or later Pro models, iPad Pro 2020+) — the Simulator has no LiDAR and ARKit scene reconstruction cannot run there. UI/rendering work can still be iterated on in the Simulator using synthetic mesh fixtures; actual scanning cannot.

## Setup

```bash
cd ScanArt
xcodegen generate
open ScanArt.xcodeproj
```

Then in Xcode:
1. Select the `ScanArt` target → **Signing & Capabilities** → choose your team (code signing is set to Automatic; a team just needs to be picked).
2. Select a physical LiDAR-capable device as the run destination.
3. Build & run.

The project has **no external dependencies to fetch** — every package is a local Swift Package under `Packages/`, so there's no `Package.resolved` network step.

## Running the algorithm unit tests

The math-heavy core (`ScanArtAlgorithms`) has no dependency on iOS/ARKit/SwiftData, so its tests can run on plain macOS without a device or simulator:

```bash
cd Packages/ScanArtAlgorithms
swift test
```

Xcode's Test Navigator should also discover and run the same tests once the project is generated, since it's a local Swift Package dependency of the app target.

## Project layout

```
ScanArt/
  project.yml              XcodeGen manifest — the source of truth for the Xcode project
  App/                      Thin SwiftUI app target: screens + view models only
  Packages/
    ScanArtAlgorithms/      Pure math: ICP alignment, thickness calc, stats, color mapping (no iOS deps — tested on macOS)
    ScanArtCore/            SwiftData models, repository protocols, DI container, shared errors
    ScanArtAR/               ARKit session management, mesh capture, world-map relocalization
    ScanArtRendering/        Metal-based 3D heat-map mesh viewer (offline Analysis screen)
    ScanArtExport/            DXF/OBJ/PLY/STL/USDZ/CSV/JSON exporters + PDF report generator
    ScanArtPersistence/       SwiftData stack, on-disk project folder layout, binary mesh storage
    ScanArtUI/                Dark/industrial/glass design system + shared components
  docs/                     This documentation set
```

Dependency direction is one-way: `ScanArtAlgorithms` and `ScanArtCore` have no dependencies on each other's siblings; `ScanArtAR`, `ScanArtRendering`, `ScanArtExport`, `ScanArtUI` depend on `ScanArtAlgorithms`; `ScanArtPersistence` depends on `ScanArtCore`; the `App` target depends on everything. See `docs/ARCHITECTURE.md` for the full rationale.

## Two decisions worth knowing about before you read the code

1. **Alignment doesn't use plain ICP on the whole mesh.** Running ICP between the pre- and post-plaster scans directly would minimize the very thickness signal being measured — it would slide the new wall back onto the old one. Alignment instead relies primarily on ARKit's own `ARWorldMap` relocalization (both scans captured in the same real-world coordinate frame), with ICP used only as a refinement restricted to non-wall reference geometry (floor/ceiling/window/door). Full rationale in `ScanArtAlgorithms/Alignment/ICPAligner.swift`'s doc comment and in `docs/ARCHITECTURE.md`.

2. **The 3D viewer uses a hand-written Metal pipeline, not RealityKit.** The spec suggested RealityKit; this implementation uses Metal directly for the per-vertex heat-map-colored mesh renderer, both for full control over vertex coloring and because it's testable/reasoned-about without needing to guess at higher-level framework behavior. See `docs/ARCHITECTURE.md`.

## Known risk areas

Being upfront about where an actual build is most likely to surface issues, roughly in order of concern:

- **Metal shader loading from the SPM package resource bundle.** `ScanArtRendering` declares its `.metal` file as a package resource; `MeshRenderer` tries to load it as a precompiled bundle library first, and falls back to compiling an embedded source string at runtime if that fails (see `ShaderSource.swift`). This fallback exists specifically because SPM's handling of Metal shader compilation via Xcode has been known to be inconsistent across toolchain versions — if the primary path fails, the fallback should still get the viewer working, but it's worth watching the console for the `assertionFailure` this code path guards.
- **ARKit buffer layout parsing.** `MeshAnchorConverter.swift` reads raw `MTLBuffer` contents from `ARGeometrySource`/`ARGeometryElement` using documented stride/offset/format fields rather than a convenience API (none exists for this). This is the single piece of code most directly translating undocumented-by-example raw memory layout into Swift, and is worth extra scrutiny if the captured mesh looks corrupted.
- **DXF color fidelity.** `DXFExporter` maps heat-map RGB colors to the nearest of a small hand-picked set of standard AutoCAD Color Index (ACI) entries, not the full 255-entry ACI table — geometry and thickness-band *classification* (via layer name) are exact; on-screen *color* in the DXF viewer is an approximation. Noted as a Phase 2 upgrade in the roadmap.
- **Everything else** is written against well-established, stable APIs (SwiftData, SwiftUI, Foundation file I/O, Core Graphics/PDF, ModelIO) that are much less likely to have surprises, but again: none of it has been compiled yet.

## What's deliberately not in Phase 1

Arbitrary-pair scan comparison UI (the data model supports it via `ThicknessResult.comparedAgainstScanID`; Phase 1's UI always compares a rescan to the project's original scan), Face ID/passcode project locking (the `Project.isLocked` flag exists; enforcement UI doesn't yet), an app icon (no image-generation tooling was available in this environment), and several other items — see `docs/ROADMAP.md` for the complete list.
