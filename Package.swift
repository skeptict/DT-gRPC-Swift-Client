// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrawThingsClient",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DrawThingsClient",
            targets: ["DrawThingsClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.23.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
        .package(url: "https://github.com/google/flatbuffers.git", exact: "25.9.23"),
        .package(url: "https://github.com/weiyanlin117/swift-fpzip-support.git", revision: "0ec6d4668c9c83bc3da0f8b2d6dfc46da0b98609"),
    ],
    targets: [
        .target(
            name: "DrawThingsClient",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "FlatBuffers", package: "flatbuffers"),
                .product(name: "C_fpzip", package: "swift-fpzip-support"),
            ]
        ),
        .testTarget(
            name: "DrawThingsClientTests",
            dependencies: ["DrawThingsClient"]
        ),
    ]
)