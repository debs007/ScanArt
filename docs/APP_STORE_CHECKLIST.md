# App Store Submission Checklist

Not exhaustive, but covers the items specific to this app's shape (LiDAR-only, fully offline, no account system) that are easy to miss.

## Before archiving

- [ ] **App icon.** No `Assets.xcassets`/`AppIcon` is included in this delivery (no image-generation tooling was available while building this). Add one before archiving — Xcode will otherwise block App Store submission (though it will still build and run on-device without one).
- [ ] **`PrivacyInfo.xcprivacy`.** Not yet included. Required by Apple for apps using "required-reason" APIs; this app's use of `FileManager` APIs for storage-availability checks (`ProjectFolderManager.availableCapacityMB()`) likely qualifies. Review against Apple's current required-reason API list at submission time, since that list is updated periodically.
- [ ] **Test on the actual minimum supported hardware** (oldest LiDAR-capable device you intend to support) — this codebase has never been run on any device.
- [ ] **Verify `NSCameraUsageDescription` wording** in `Info.plist` reads naturally in context — it currently mentions LiDAR explicitly, which is accurate but worth double-checking against how Apple's review team responds to it.

## App Review notes (write these into the App Store Connect submission)

- **Reviewers likely won't have LiDAR-capable hardware on hand**, and the app is non-functional without it past the Splash screen's device gate. Strongly consider:
  - A demo video showing a full scan → rescan → analysis → export flow, attached to the review notes.
  - Explicit reviewer notes explaining the LiDAR requirement and that the "This device is not supported" screen is expected, correct behavior on non-LiDAR hardware/Simulator — not a bug.
- **No account system, no backend** — review notes can state plainly that there's nothing to log into and no server-side component to review.

## Export compliance

- App does not use custom/proprietary encryption beyond what's provided by standard OS frameworks (the local `.scanmesh`/`.worldmap` files are compressed, not encrypted). `Info.plist` already sets `ITSAppUsesNonExemptEncryption` to `false`. Re-verify this is still accurate if encryption is ever added (e.g., for a future project-lock feature).

## Privacy

- **Camera usage** is scoped to AR scanning only — no photo library access, no background camera use. `NSCameraUsageDescription` covers this.
- **No data leaves the device.** There's no analytics SDK, no crash reporter, no network calls anywhere in this codebase (`NSAppTransportSecurity` is set to disallow arbitrary loads). App Store Connect's "App Privacy" questionnaire should reflect "Data Not Collected" across the board, assuming no third-party SDK is added later without revisiting this.
- **Photo library** — if the Phase 2 photo-attachment-to-reports feature is built (see `ROADMAP.md`), this section needs revisiting for `NSPhotoLibraryUsageDescription` and the corresponding App Privacy disclosure.

## Screenshots & metadata

- Screenshots should be captured on-device after a real scan, ideally showing: the live scanning view with coverage indicator, the heat-map 3D viewer with the color legend visible, and a generated PDF report page. Marketing/App Store screenshots are not part of this codebase delivery.
- Suggest a TestFlight beta phase specifically with real end users (contractors/engineers) given how dependent this app's core value is on real-world scanning conditions (lighting, surface texture, room layout) that are hard to fully anticipate from a desk.
