// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LocalModelImport", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../shared/packages/OfflineCore")], targets: [.executableTarget(name: "LocalModelImport", dependencies: [.product(name: "OfflineCore", package: "OfflineCore")])])
