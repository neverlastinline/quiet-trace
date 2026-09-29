// swift-tools-version: 5.9
// Everything in Quiet Trace that isn't UIKit: the drawings, how they're measured,
// how tracing is checked, which touch is drawing, what comes next, and the chime.
// Plain Swift + Foundation, so it builds and tests on macOS and Linux alike.
import PackageDescription

let package = Package(
    name: "QuietTraceKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "QuietTraceKit", targets: ["QuietTraceKit"]),
    ],
    targets: [
        .target(name: "QuietTraceKit"),
        .testTarget(
            name: "QuietTraceKitTests",
            dependencies: ["QuietTraceKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
