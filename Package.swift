// swift-tools-version: 6.2
// 앱 전체를 하나의 Swift 패키지로 빌드한다. 기능 모듈은 Packages/ 아래 타깃으로 나눈다.
// .app 묶음 만들기·서명은 scripts/build.sh가 맡는다(Xcode에서 이 파일을 열어도 된다).
import PackageDescription

let package = Package(
    name: "Mactatus",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Mactatus", targets: ["Mactatus"]),
    ],
    targets: [
        .target(
            name: "CoreKit",
            path: "Packages/CoreKit/Sources/CoreKit"
        ),
        .target(
            name: "UsageKit",
            dependencies: ["CoreKit"],
            path: "Packages/UsageKit/Sources/UsageKit"
        ),
        .target(
            name: "MetricsKit",
            path: "Packages/MetricsKit/Sources/MetricsKit"
        ),
        .target(
            name: "DrawerKit",
            path: "Packages/DrawerKit/Sources/DrawerKit"
        ),
        .target(
            name: "NotchKit",
            path: "Packages/NotchKit/Sources/NotchKit"
        ),
        .target(
            name: "Modules",
            dependencies: ["CoreKit", "NotchKit"],
            path: "Packages/Modules/Sources/Modules"
        ),
        .executableTarget(
            name: "Mactatus",
            dependencies: ["CoreKit", "UsageKit", "MetricsKit", "DrawerKit", "NotchKit", "Modules"],
            path: "App"
        ),
        .testTarget(
            name: "DrawerKitTests",
            dependencies: ["DrawerKit"],
            path: "Packages/DrawerKit/Tests/DrawerKitTests"
        ),
        .testTarget(
            name: "NotchKitTests",
            dependencies: ["NotchKit"],
            path: "Packages/NotchKit/Tests/NotchKitTests"
        ),
        .testTarget(
            name: "ModulesTests",
            dependencies: ["Modules"],
            path: "Packages/Modules/Tests/ModulesTests"
        ),
        .testTarget(
            name: "MetricsKitTests",
            dependencies: ["MetricsKit"],
            path: "Packages/MetricsKit/Tests/MetricsKitTests"
        ),
        .testTarget(
            name: "UsageKitTests",
            dependencies: ["UsageKit"],
            path: "Packages/UsageKit/Tests/UsageKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
