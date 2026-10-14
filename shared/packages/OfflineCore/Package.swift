// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "OfflineCore", platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [.library(name: "OfflineCore", targets: ["OfflineCore"])],
    targets: [.target(name: "ArchiveRuntime", linkerSettings: [.linkedLibrary("bz2")]),
              .target(name: "LanguageIdentificationRuntime", exclude: ["vendor/LICENSE", "vendor/README.md"]),
              .target(name: "OfflineCore", dependencies: ["ArchiveRuntime", "LanguageIdentificationRuntime"], resources: [.process("Resources")]),
              .testTarget(name: "OfflineCoreTests", dependencies: ["OfflineCore"], resources: [.process("Fixtures")])],
    cxxLanguageStandard: .cxx17)
