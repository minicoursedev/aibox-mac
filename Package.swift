// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIBoxMac",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AIBox", targets: ["AIBox"]),
        .executable(name: "aibox-notify", targets: ["AIBoxNotify"]),
    ],
    targets: [
        .target(name: "AIBoxCore", exclude: ["Remote/tests", "Remote/README.md"], resources: [.process("Resources"), .copy("Remote/notify.py"), .copy("Remote/prepare.py")]),
        .executableTarget(name: "AIBox", dependencies: ["AIBoxCore"]),
        .executableTarget(name: "AIBoxNotify", dependencies: ["AIBoxCore"]),
        .testTarget(name: "AIBoxCoreTests", dependencies: ["AIBoxCore"]),
    ]
)
