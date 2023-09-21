// swift-tools-version: 5.6

import PackageDescription

let package = Package(
  name: "Kubrick",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .watchOS(.v7),
    .tvOS(.v15)
  ],
  products: [
    .library(
      name: "Kubrick",
      targets: ["Kubrick"]),
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftyLab/AsyncObjects.git", .upToNextMinor(from: "2.1.0")),
    .package(url: "https://github.com/outfoxx/potentcodables.git", .upToNextMinor(from: "3.1.1")),
    .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMinor(from: "6.18.0")),
    .package(url: "https://github.com/kdubb/SwiftFriendlyId.git", .upToNextMinor(from: "1.3.1")),

    // TESTING DEPENDENCIES
    .package(url: "https://github.com/outfoxx/sunday-swift.git", .upToNextMinor(from: "1.0.0-beta.26"))
  ],
  targets: [
    .target(
      name: "Kubrick",
      dependencies: [
        .product(name: "AsyncObjects", package: "AsyncObjects"),
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "PotentCodables", package: "potentcodables"),
        .product(name: "FriendlyId", package: "SwiftFriendlyId")
      ]
    ),
    .testTarget(
      name: "KubrickTests",
      dependencies: [
        "Kubrick",
        .product(name: "SundayServer", package: "sunday-swift")
      ]),
  ]
)
