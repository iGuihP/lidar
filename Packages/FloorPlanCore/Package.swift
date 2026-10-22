// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FloorPlanCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FloorPlanCore", targets: ["FloorPlanCore"])
    ],
    targets: [
        .target(name: "FloorPlanCore"),
        .testTarget(name: "FloorPlanCoreTests", dependencies: ["FloorPlanCore"])
    ]
)
