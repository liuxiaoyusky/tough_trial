// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToughTrial",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FocusTimelineCore", targets: ["FocusTimelineCore"])
    ],
    targets: [
        .target(name: "FocusTimelineCore"),
        .executableTarget(
            name: "FocusTimelineCoreChecks",
            dependencies: ["FocusTimelineCore"],
            path: "Checks/FocusTimelineCoreChecks"
        )
    ]
)
