// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContainerDesktop",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // SwiftTerm — full xterm/VT100 terminal emulator
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
    ],
    targets: [
        // Library target — all app code except the @main entry point.
        // Tests import this directly without triggering NSApplication.
        .target(
            name: "ContainerDesktop",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/ContainerDesktop",
            exclude: ["Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),

        // Executable target — thin entry point that calls ContainerDesktopApp.main().
        .executableTarget(
            name: "ContainerDesktopApp",
            dependencies: ["ContainerDesktop"],
            path: "Sources/ContainerDesktopApp",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/ContainerDesktop/Info.plist",
                ]),
            ]
        ),

        // Tests depend on the library, not the executable.
        .testTarget(
            name: "ContainerDesktopTests",
            dependencies: ["ContainerDesktop"],
            path: "Tests/ContainerDesktopTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
