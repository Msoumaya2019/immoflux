// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ImmoCore", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ImmoCore", targets: ["ImmoCore"])],
    targets: [.target(name: "ImmoCore"), .testTarget(name: "ImmoCoreTests", dependencies: ["ImmoCore"])])
