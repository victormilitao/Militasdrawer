// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MilitasdrawerCore",
    products: [.library(name: "MilitasdrawerCore", targets: ["MilitasdrawerCore"])],
    targets: [
        .target(name: "MilitasdrawerCore", path: "Militasdrawer/Core"),
        .testTarget(name: "CoreTests", dependencies: ["MilitasdrawerCore"], path: "Tests/CoreTests")
    ]
)
