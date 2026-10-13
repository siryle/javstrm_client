// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JavStrm",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "JavStrmCore", targets: ["JavStrmCore"])],
    targets: [
        .target(name: "JavStrmCore"),
        .executableTarget(
            name: "JavStrmVerification",
            dependencies: ["JavStrmCore"],
            path: "Tests/JavStrmCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
