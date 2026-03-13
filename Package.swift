// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenGarden",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenGarden",
            path: "TokenGarden",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "TokenGarden/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "TokenGardenTests",
            dependencies: ["TokenGarden"],
            path: "TokenGardenTests"
        ),
    ]
)
