// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EigoMaster",
    defaultLocalization: "ja",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EigoMaster", targets: ["EigoApp"]),
        .executable(name: "eigo-tool", targets: ["EigoTool"]),
        .library(name: "EigoCore", targets: ["EigoCore"]),
    ],
    targets: [
        // UI 非依存のロジック（コンテンツ形式・SRS・進捗・更新・AI添削）。将来 iOS 版でも再利用可能。
        .target(
            name: "EigoCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // macOS アプリ本体（SwiftUI）
        .executableTarget(
            name: "EigoApp",
            dependencies: ["EigoCore"],
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // コンテンツ検証・manifest 生成用 CLI
        .executableTarget(
            name: "EigoTool",
            dependencies: ["EigoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EigoCoreTests",
            dependencies: ["EigoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
