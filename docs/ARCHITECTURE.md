# Architecture

## Module graph

```
                     ┌─────────────────┐
                     │  ScanArtAlgorithms │  (no dependencies — pure Foundation + simd)
                     └────────┬─────────┘
                ┌─────────────┼─────────────────┬──────────────┐
                │              │                 │              │
        ┌───────▼──────┐ ┌────▼────────┐ ┌──────▼──────┐ ┌─────▼─────┐
        │  ScanArtAR   │ │ScanArtRender │ │ScanArtExport │ │ ScanArtUI │
        └──────────────┘ └─────────────┘ └───────▲──────┘ └───────────┘
                                                    │
        ┌──────────────┐                    ┌──────┴──────┐
        │  ScanArtCore │────────────────────▶ScanArtPersist│
        └──────┬───────┘                    └─────────────┘
               │
               └───────────────────┐
                                    ▼
                              App target
                    (depends on every package above)
```

- **`ScanArtAlgorithms`** has zero dependencies — not even Foundation-adjacent iOS frameworks — deliberately, so its test suite runs on plain macOS (`swift test`, no simulator, no device). Every geometry/statistics/color algorithm lives here.
- **`ScanArtCore`** holds the SwiftData models, repository *protocols* (not implementations), the DI container, and the shared error type. It has no dependency on `ScanArtAlgorithms` — the data model doesn't need to know how thickness is computed, only how to store the result.
- **`ScanArtAR`**, **`ScanArtRendering`**, **`ScanArtExport`**, **`ScanArtUI`** each depend on `ScanArtAlgorithms` (they all consume `MeshBuffer`/`ThicknessSample`/etc.) but not on each other or on `ScanArtCore` — none of them need to know what a "Project" is.
- **`ScanArtPersistence`** depends on `ScanArtCore` (it implements the repository protocols and manages `MeshBuffer` file I/O) and `ScanArtAlgorithms` (to serialize `MeshBuffer`/`ThicknessSample`).
- The **App target** is deliberately thin: SwiftUI views + view models only. No algorithm, no persistence detail, no export format logic lives in `App/` — it orchestrates the packages.

This one-way dependency graph is what makes `ScanArtAlgorithms`' tests runnable without a simulator, and it's what makes each package's job legible in isolation: if you're reading `ScanArtExport`, you never need to wonder whether it secretly reaches into SwiftData.

## Patterns

**MVVM + Repository.** Every screen in `App/Features/` has a `View` and, where there's real logic (not a static form), a `@MainActor` `ObservableObject` view model. View models talk to SwiftData exclusively through the repository protocols defined in `ScanArtCore/Protocols/RepositoryProtocols.swift`, never through a raw `ModelContext`. This is what makes it possible to reason about (and eventually unit-test) view model logic without spinning up SwiftData at all — a fake repository conforming to the same protocol is enough.

**Dependency injection.** `DIContainer` (in `ScanArtCore`) holds the four repositories and is injected into the SwiftUI environment once, in `ScanArtApp.swift`, via a custom `EnvironmentKey`. Views read it with `@Environment(\.diContainer)`.

## Concurrency design

This is the part of the architecture most worth understanding before changing anything.

- **SwiftData models are `@MainActor`-confined, on purpose.** `@Model` classes (`Project`, `ScanRecord`, `ThicknessResult`, `ReportRecord`) are not safely `Sendable` — much like Core Data's `NSManagedObject`, touching one off its owning context's thread/actor is unsafe. Rather than fighting this, every repository protocol in `ScanArtCore` is `@MainActor`-bound, and every view model that touches persistence is `@MainActor`. This is a deliberate simplification: the app never has SwiftData objects crossing actor boundaries, so there's no risk category to reason about there at all.
- **Heavy computation lives in `ScanArtAlgorithms`, which touches none of the above.** `MeshBuffer`, `ThicknessSample`, `AlignmentResult`, `ThicknessStatistics` — every type that flows through ICP alignment and thickness calculation is a plain, `Sendable` value type. This is what lets `ThicknessCalculator.compute` fan out across a `TaskGroup` freely, and what lets view models hop work onto `Task.detached` for the genuinely expensive steps (mesh compression to disk, ICP refinement, thickness sampling) without any actor-isolation ceremony.
- **The pattern used throughout the view models:** gather/compute on a background `Task.detached` using only `Sendable` value types (`MeshBuffer`, `[ThicknessSample]`, `URL`, etc.), `await` the result back on the view model's own `@MainActor` context, *then* touch SwiftData through a repository. `AnalysisViewModel.generateThicknessMap()` is the clearest example of this shape.
- **One deliberate exception:** `AnalysisViewModel.generateReport()` calls `PDFReportGenerator.generate` directly on the main actor rather than via `Task.detached`, specifically *because* `ReportContent` (its input) holds live `Project`/`ScanRecord` references for convenience — moving that call off the main actor would have reintroduced the exact SwiftData-threading problem described above for a relatively lightweight operation (a few pages of Core Graphics drawing). Worth revisiting if reports grow to include many large embedded photos.
- **Nested `ObservableObject` propagation.** Several screens (`Scan`, `Rescan`, `Analysis`) construct their view model lazily in `.onAppear`, once `@Environment(\.diContainer)` is available (it isn't yet at `View.init()` time) — via a small `...Box: ObservableObject` holding an optional `vm`. A plain `@Published var vm: SomeViewModel?` is *not* suffient on its own: it only fires when the `vm` slot itself is reassigned, not when a `@Published` property *inside* the view model changes. Each box explicitly re-subscribes to `vm?.objectWillChange` and forwards it (`ScanViewModelBox`, `RescanViewModelBox`, `AnalysisViewModelBox` in the corresponding View files). `ScanViewModel`/`RescanViewModel` do the same one level deeper, forwarding `ARScanSessionManager`'s `objectWillChange` (tracking state, coverage %, mesh anchor count all live there) — without this, the live scanning overlay would appear frozen.

## The two big judgment calls

### 1. Alignment strategy

The spec asks for automatic scan alignment. The naive approach — run ICP (Iterative Closest Point) between the pre-plaster and post-plaster meshes — is actively wrong for this problem: ICP's objective is to *minimize* point-to-point distance between the two point sets, but the entire point of the app is that the wall surface has moved outward by the plaster thickness. Unconstrained ICP will happily converge to a transform that sides the new wall back onto the old one, deflating every thickness measurement toward zero — silently producing a measurement tool that under-reports the exact thing it's meant to measure.

The fix has two parts:
- **Primary alignment is `ARWorldMap` relocalization.** The original scan saves its `ARWorldMap` (ARKit's spatial map of the room, including visual feature points). Starting a rescan loads that same world map as the new session's `initialWorldMap`; ARKit's own visual-inertial relocalization then places the new session in *the same real-world coordinate frame* as the original, using camera imagery and motion data — not mesh geometry — to find that alignment. No naive-ICP bias risk, because geometry never enters into it.
- **ICP is used only as a refinement**, and only ever on faces classified as stable reference geometry (floor, ceiling, window, door — via `MeshRegionClass.isStableReference`), *never* on wall faces (the measurement target). See `ICPAligner.swift`'s doc comment for the enforcement point (`MeshBuffer.filteredByFace`) and `RescanViewModel.finishAndSave` for where it's actually invoked.

### 2. Metal instead of RealityKit for the 3D viewer

The spec suggests RealityKit for rendering. This implementation uses a hand-written Metal pipeline (`ScanArtRendering`) instead, for two reasons: RealityKit's exact API surface for per-vertex custom color (as opposed to texture-mapped materials) wasn't something that could be verified with full confidence in an environment without a compiler to check against, and the spec's own performance requirements (60fps with dense LiDAR meshes) are a reasonable independent justification for direct Metal control regardless. The tradeoff is more code (a full render pipeline, vertex descriptor, and shader pair) in exchange for a rendering path built entirely from well-documented, stable Metal APIs.

Live AR camera passthrough during *scanning* (as opposed to the offline Analysis viewer) uses `ARSCNView` (SceneKit) instead, for a different reason: camera passthrough plus ARKit's built-in scene-reconstruction debug visualization (`ARSCNDebugOptions.showSceneUnderstanding`) is a well-documented pattern that avoids re-deriving a second, parallel mesh-to-GPU-geometry pipeline for a live view that gets replaced by the Metal viewer the moment capture ends anyway. See `ARCameraView.swift`'s doc comment.

## Storage architecture

SwiftData holds metadata only — never mesh geometry or per-vertex sample data. `Project`, `ScanRecord`, `ThicknessResult`, `ReportRecord` are all small, fast-to-query rows; the megabytes-large data (meshes, thickness samples, world maps) lives as flat files on disk, referenced by filename. See `DATABASE_SCHEMA.md` for the full field-level layout and the on-disk folder structure.
