// swift-tools-version:5.9
import PackageDescription

// Glance: a menu-bar-only screen helper.
//
// GlanceCore holds every piece of logic that does not need AppKit (parsing the
// AI's reply, the show/hide switch, coordinate maths, snapping to text, the
// cloud/backup race, building HTTP requests) so it can be unit-tested with
// `swift test`. The Glance target is the app shell around it.
let package = Package(
    name: "Glance",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "Glance", dependencies: ["GlanceCore"]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
