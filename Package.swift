// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeatFlowMetal",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HeatFlow", targets: ["HeatFlow"]),
        .executable(name: "heatflow", targets: ["HeatFlowCLI"])
    ],
    targets: [
        .target(name: "HeatFlow", resources: [.copy("Shaders/heat.metal")]),
        .executableTarget(name: "HeatFlowCLI", dependencies: ["HeatFlow"]),
        .testTarget(name: "HeatFlowTests", dependencies: ["HeatFlow"])
    ]
)
