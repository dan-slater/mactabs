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
            dependencies: ["Fretboard", "NoteJudge"],
            path: "Sources/MacTabs"
        ),
        // Hears whether an expected note was played (pure DSP, shared by the app and the bench).
        .target(name: "NoteJudge", path: "Sources/NoteJudge"),
        // Offline scoring of NoteJudge against a chart + recording; also renders test audio.
        .executableTarget(name: "pitchbench", dependencies: ["NoteJudge"], path: "Sources/pitchbench"),
    ]
)
