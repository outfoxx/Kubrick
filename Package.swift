// swift-tools-version: 5.6

import PackageDescription

let package = Package(
  name: "Kubrick",
  platforms: [
    .macOS(.v12),
    .iOS(.v15),
    .tvOS(.v15),
    .watchOS(.v8)
  ],
  products: [
    .library(name: "Kubrick", targets: ["Kubrick"]),
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftyLab/AsyncObjects.git", .upToNextMinor(from: "2.1.0")),
    .package(url: "https://github.com/outfoxx/potentcodables.git", .upToNextMinor(from: "3.2.0")),
    .package(url: "https://github.com/kdubb/SwiftFriendlyId.git", .upToNextMinor(from: "1.3.1")),
    .package(url: "https://github.com/outfoxx/IOStreams.git", .upToNextMinor(from: "1.4.2")),

    .package(url: "https://github.com/apple/swift-docc-plugin", .upToNextMinor(from: "1.3.0")),

    // Test Pacakges
    .package(url: "https://github.com/outfoxx/sunday-swift.git", .upToNextMinor(from: "1.0.0-beta.29")),
  ],
  targets: [
    .target(
      name: "Kubrick",
      dependencies: [
        .product(name: "AsyncObjects", package: "AsyncObjects"),
        .product(name: "IOStreams", package: "iostreams"),
        .product(name: "PotentCodables", package: "potentcodables"),
        .product(name: "FriendlyId", package: "SwiftFriendlyId")
      ],
      resources: [
        .process("Kubrick.docc")
      ]
    ),
    .testTarget(
      name: "KubrickTests",
      dependencies: [
        "Kubrick",
        .product(name: "SundayServer", package: "sunday-swift")
      ]
    )    
  ]
)
