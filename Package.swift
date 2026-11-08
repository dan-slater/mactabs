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
        // Basic Pitch's compiled CoreML model (Apache-2.0, Spotify) ships with it, licence alongside.
        .target(name: "NoteJudge", path: "Sources/NoteJudge",
                resources: [.copy("Model/nmp.mlmodelc"), .copy("Model/LICENSE-basic-pitch")]),
        // Offline scoring of NoteJudge against a chart + recording; also renders test audio.
        .executableTarget(name: "pitchbench", dependencies: ["NoteJudge"], path: "Sources/pitchbench"),
    ]
)
