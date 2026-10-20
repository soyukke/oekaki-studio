// swift-tools-version: 5.9
import PackageDescription

// The pixel algorithms live in core/core.kizu. `make core` compiles them to
// build/core.o, which is linked in here.
let coreObject = "\(Context.packageDirectory)/build/core.o"

let package = Package(
    name: "OekakiStudio",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "COekakiCore",
            linkerSettings: [.unsafeFlags(["-Xlinker", coreObject])]
        ),
        .target(name: "OekakiKit", dependencies: ["COekakiCore"]),
        .executableTarget(name: "OekakiApp", dependencies: ["OekakiKit"]),
        .executableTarget(name: "OekakiPV", dependencies: ["OekakiKit"]),
        .testTarget(name: "OekakiKitTests", dependencies: ["OekakiKit"]),
    ]
)
