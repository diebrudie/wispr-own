// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WisprOwn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WisprOwn",
            dependencies: ["whisper"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        // Vendored by Scripts/fetch-whisper.sh (run `make setup`).
        .binaryTarget(name: "whisper", path: "Vendor/whisper.xcframework"),
    ]
)
