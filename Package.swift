// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MilitasdrawCore",
    products: [.library(name: "MilitasdrawCore", targets: ["MilitasdrawCore"])],
    targets: [
        .target(name: "MilitasdrawCore", path: "Militasdrawer/Core"),
        .testTarget(name: "CoreTests", dependencies: ["MilitasdrawCore"], path: "Tests/CoreTests")
    ]
)
