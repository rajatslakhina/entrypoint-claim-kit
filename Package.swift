// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EntrypointClaimKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "EntrypointClaimKit", targets: ["EntrypointClaimKit"]),
        .executable(name: "EntrypointClaimDemo", targets: ["EntrypointClaimDemo"])
    ],
    dependencies: [
        .package(url: "https://github.com/rajatslakhina/dockerfile-claim-kit.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "EntrypointClaimKit",
            dependencies: [.product(name: "DockerfileClaimKit", package: "dockerfile-claim-kit")]
        ),
        .executableTarget(
            name: "EntrypointClaimDemo",
            dependencies: ["EntrypointClaimKit"]
        ),
        .testTarget(
            name: "EntrypointClaimKitTests",
            dependencies: ["EntrypointClaimKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
