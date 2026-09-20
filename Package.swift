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
        .library(name: "ToughTrialV2Core", targets: ["ToughTrialV2Core"]),
        .library(name: "ToughTrialAppShared", targets: ["ToughTrialAppShared"]),
        .library(name: "ToughTrialActivityShared", targets: ["ToughTrialActivityShared"])
    ],
    targets: [
        .target(name: "ToughTrialAppShared", dependencies: ["ToughTrialV2Core"]),
        .testTarget(name: "ToughTrialWorkspaceTests", dependencies: ["ToughTrialAppShared", "ToughTrialV2Core"]),
        .testTarget(name: "ToughTrialCaptureTests", dependencies: ["ToughTrialV2Core"], path: "Tests/ToughTrialCaptureTests"),
        .testTarget(name: "ToughTrialScheduleLiveTests", dependencies: ["ToughTrialV2Core"],
                    path: "Tests/ToughTrialScheduleLiveTests"),
        .executableTarget(name: "ToughTrialScheduleRunner", dependencies: ["ToughTrialV2Core"]),
        .testTarget(
            name: "ToughTrialSpeechTests",
            dependencies: ["ToughTrialV2Core"],
            path: "Tests/ToughTrialSpeechTests"
        ),
        .target(name: "FocusTimelineCore"),
        .target(name: "ToughTrialV2Core"),
        .target(name: "ToughTrialActivityShared"),
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
