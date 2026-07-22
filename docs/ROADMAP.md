# Roadmap

Phase 1 (this delivery) is a complete, working core: create a project, capture an original scan, capture a rescan with relocalization-based alignment, generate a thickness map, view it as a 3D heat map with statistics, export to 7 formats, and generate a PDF report. Everything below is deliberately out of scope for Phase 1, roughly ordered by how soon it's likely to matter.

## Phase 2 candidates

- **Face ID / passcode project locking.** `Project.isLocked` exists in the data model; there's no enforcement UI yet (lock/unlock screen, biometric gate on project open, `NSFaceIDUsageDescription` in Info.plist). Straightforward to add once prioritized — the model already round-trips the flag.
- **Arbitrary multi-scan comparison UI.** `ThicknessResult.comparedAgainstScanID` already supports comparing any two scans, not just "rescan vs. original" — Phase 1's Analysis screen always picks the project's original scan as the baseline. A picker to choose both sides of a comparison (e.g., "Scan 3 vs. Scan 9") is a UI-only addition on top of the existing data model and `ThicknessCalculator` call.
- **QEM-based mesh decimation.** The current decimator (`MeshDecimator.swift`) uses grid-based vertex clustering, which is simple and correct but loses detail faster than quadric-error-metric decimation at aggressive reduction ratios. Worth upgrading if very large scans need heavier decimation for viewer performance without visible quality loss.
- **Full 255-entry ACI color matching for DXF export.** Currently maps to the nearest of ~9 standard AutoCAD Color Index colors; the layer *name* always carries the exact thickness-band classification regardless, but on-screen color in the DXF viewer is an approximation. A full ACI RGB lookup table would make the color exact too.
- **Vertex-color-in-USDZ.** Current USDZ export is geometry-only (position + normal) — Model I/O's material model is texture/PBR-oriented rather than exposing a simple per-vertex-color channel the way PLY does. Baking the heat map into a vertex-color texture (or per-triangle-averaged material regions) would bring USDZ export to color parity with PLY/DXF.
- **Advanced measurement tools:** cross-section / line-profile view (pick two points on the wall, see a thickness graph along that line), custom palette editor UI (the color-stop data model already supports arbitrary stops; there's no in-app editor for them), DXF layer customization UI.
- **Side-by-side / occlusion-aware comparison view** in the 3D viewer (original and rescan mesh both visible, with the ability to peel/slice between them) as an alternative to the single heat-map-colored surface.

## Phase 3 / longer-term

- **Localization** — all UI strings are currently hardcoded English.
- **BIM / Revit-native interchange** beyond DXF (e.g., IFC export) for firms with a full BIM pipeline.
- **Optional cloud sync** — explicitly out of scope for the current "no backend, no cloud, fully offline" design; would need real product/privacy decisions (what syncs, account model, conflict resolution) before any implementation work, not just an engineering add-on.
- **CoreML-based scan quality guidance** — e.g., real-time feedback distinguishing "textured enough to track well" from "too reflective/uniform," beyond the current tracking-state-based heuristics in `ScanQualityAnalyzer`.
