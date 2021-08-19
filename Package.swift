// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
        name: "Swift_Coroutine",
        products: [
            // Products define the executables and libraries produced by a package, and make them visible to other packages.
            .library(
                    name: "Swift_Coroutine",
                    type: .dynamic,
                    targets: ["Swift_Coroutine"]),
        ],
        dependencies: [
            // Dependencies declare other packages that this package depends on.
            // .package(url: /* package url */, from: "1.0.0"),
            .package(url: "https://hub.fastgit.org/Guang1234567/RxSwift.git", .branch("android_support")),
            .package(url: "https://hub.fastgit.org/Guang1234567/Swift_Boost_Context.git", .branch("master")),
            .package(url: "https://hub.fastgit.org/Guang1234567/Swift_Atomics.git", .branch("master"))
        ],
        targets: [
            // Targets are the basic building blocks of a package. A target can define a module or a test suite.
            // Targets can depend on other targets in this package, and on products in packages which this package depends on.
            .target(
                    name: "Swift_Coroutine",
                    dependencies: [
                        "Swift_Boost_Context",
                        "Swift_Atomics",
                        "RxSwift",
                        .product(name: "RxRelay", package: "RxSwift"),
                        .product(name: "RxBlocking", package: "RxSwift")
                    ]),
            .target(
                    name: "Example",
                    dependencies: ["Swift_Coroutine"]),
            .testTarget(
                    name: "Swift_CoroutineTests",
                    dependencies: ["Swift_Coroutine"]),
        ]
)
