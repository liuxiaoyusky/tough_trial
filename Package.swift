// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToughTrial",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FocusTimelineCore", targets: ["FocusTimelineCore"]),
        .library(name: "ToughTrialV2Core", targets: ["ToughTrialV2Core"])
    ],
    targets: [
        .target(name: "FocusTimelineCore"),
        .target(name: "ToughTrialV2Core"),
        .executableTarget(
            name: "FocusTimelineCoreChecks",
            dependencies: ["FocusTimelineCore"],
            path: "Checks/FocusTimelineCoreChecks"
        ),
        .executableTarget(
            name: "ToughTrialV2Checks",
            dependencies: ["ToughTrialV2Core"],
            path: "Checks/ToughTrialV2Checks"
        )
    ]
)
