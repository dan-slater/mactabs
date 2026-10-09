// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacTabs",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Chord diagrams + the tombatossals chords-db (MIT).
        .package(url: "https://github.com/itsmeichigo/Fretboard.git", revision: "0803c3432702c3ffbd925fd3d0a56024d9bffe22"),
    ],
    targets: [
        .executableTarget(
            name: "MacTabs",
            dependencies: ["Fretboard"],
            path: "Sources/MacTabs"
        ),
    ]
)
