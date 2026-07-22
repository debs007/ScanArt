// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScanArtPersistence",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ScanArtPersistence", targets: ["ScanArtPersistence"])
    ],
    dependencies: [
        .package(path: "../ScanArtCore"),
        .package(path: "../ScanArtAlgorithms")
    ],
    targets: [
        .target(name: "ScanArtPersistence", dependencies: ["ScanArtCore", "ScanArtAlgorithms"])
    ]
)
