// swift-tools-version: 6.3
import PackageDescription
let package = Package(name: "ShutYourLid", platforms: [.macOS(.v14)], products: [
.executable(name: "ShutYourLid", targets: ["ShutYourLid"]), .executable(name: "LidPowerHelper", targets: ["LidPowerHelper"])], targets: [
.target(name: "LidModeFeature"),
.executableTarget(name: "ShutYourLid", dependencies: ["LidModeFeature"]),
.executableTarget(name: "LidPowerHelper", dependencies: ["LidModeFeature"]),
.testTarget(name: "ShutYourLidTests", dependencies: ["ShutYourLid", "LidModeFeature"])])
