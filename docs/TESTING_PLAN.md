# Testing Plan

## What's actually implemented right now

`Packages/ScanArtAlgorithms/Tests/ScanArtAlgorithmsTests/` — unit tests for the parts of the codebase that are pure, deterministic, and have no ARKit/SwiftUI/SwiftData dependency:

- **`ICPAlignerTests.swift`** — synthetic point clouds (a floor+wall corner) testing that alignment recovers a known translation, recovers a known small rotation+translation, and doesn't crash on insufficient overlap.
- **`ThicknessCalculatorTests.swift`** — synthetic parallel grid planes at a known offset, testing that ray-cast intersection recovers a known 4cm offset and nearest-neighbor projection recovers a known 15mm offset, that a region with no corresponding rescan surface is correctly marked invalid rather than producing a bogus value, and that computed volume matches the expected area × thickness for the synthetic geometry.
- **`ColorMapperTests.swift`** — on-target thickness maps to the expected greenish band, very-thin/extremely-thick values map toward the expected blue/red-purple ends, values beyond the last stop clamp rather than extrapolate, and the red channel increases monotonically through the green→yellow transition.

These run with plain `swift test` (see README) — no simulator or device needed, because `ScanArtAlgorithms` has zero iOS-specific dependencies by design.

## Why the rest of the codebase isn't unit-tested yet

Everything outside `ScanArtAlgorithms` depends on frameworks that fundamentally require a real environment to exercise meaningfully:

- **ARKit scene reconstruction cannot run in the Simulator at all** — there's no LiDAR to simulate, and Apple doesn't provide a synthetic scene-reconstruction data source. Any test of `ScanArtAR` beyond pure data transformation (e.g., `MeshAnchorConverter`'s buffer parsing, if given synthetic `ARMeshAnchor`-shaped input) needs a physical device.
- **SwiftData model behavior** (`ScanArtCore`/`ScanArtPersistence`) is realistically tested with an in-memory `ModelContainer` (`SwiftDataStack(inMemoryForTesting: true)` already supports this) — this is straightforward to add but wasn't prioritized over the algorithm correctness tests given limited time, since the algorithm layer is where a subtle bug would be most costly (wrong measurements) and least visible (no compiler, no way to eyeball-check geometry math the way you can eyeball a list screen).
- **Metal rendering** (`ScanArtRendering`) is inherently visual — the meaningful test is "does the heat map look right on screen," not something a unit test asserts well. Manual/visual QA on-device is the right tool here.
- **SwiftUI views** have no logic worth unit-testing in isolation beyond what their view models already cover; view model logic itself is thin (mostly orchestration of repository + algorithm calls) and would benefit most from the SwiftData in-memory approach above, once added.

## Recommended next testing investment, in priority order

1. **In-memory SwiftData repository tests** for `ScanArtPersistence` — cascade delete behavior (deleting a `Project` should remove its `ScanRecord`s, `ThicknessResult`s, and `ReportRecord`s), and that `Project.nextRescanSequenceNumber`/`originalScan`/`rescans` computed properties behave correctly as scans are added.
2. **`MeshFileStorage` round-trip tests** — save a synthetic `MeshBuffer`/`[ThicknessSample]` array to a temp file, load it back, assert equality. Pure Foundation + the `Compression` framework, no iOS-specific dependency, so this can also run via plain `swift test` if `ScanArtPersistence`'s test target is set up the same way `ScanArtAlgorithms`' is (it currently only targets iOS — would need a small platform-list change to run outside Xcode).
3. **On-device manual QA pass** covering: LiDAR-unsupported-device gate (or a device with LiDAR spoofed absent, if that's practical to test), tracking-lost recovery messaging, relocalization success and failure paths (test the failure path by rescanning in a materially different room), and a full scan → rescan → generate → export → report round trip on a real wall.
4. **Exporter output validation** — for each of DXF/OBJ/PLY/STL/USDZ, actually open the exported file in a real consumer (AutoCAD or a free DXF viewer; Preview.app or an OBJ/PLY viewer for the mesh formats; Quick Look for USDZ) rather than only trusting that the Swift code ran without throwing. This is the highest-value low-effort check once a build exists, since export correctness is easy to visually verify and impossible to fully verify by reading code.
