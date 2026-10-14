// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "SpeechRecognitionRuntime", platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "SpeechRecognitionRuntime", targets: ["SpeechRecognitionRuntime"])],
    dependencies: [.package(path: "../../../Dependencies/vendor/FluidAudio", traits: [])],
    targets: [.target(name: "SpeechRecognitionRuntime", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])])
