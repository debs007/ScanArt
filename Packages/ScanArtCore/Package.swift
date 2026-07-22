// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScanArtCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ScanArtCore", targets: ["ScanArtCore"])
    ],
    dependencies: [],
    targets: [
        .target(name: "ScanArtCore", dependencies: [])
    ]
)
