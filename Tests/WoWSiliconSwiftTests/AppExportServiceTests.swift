import XCTest
import Darwin
@testable import WoWSiliconSwift

final class AppExportServiceTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconAppExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testExportedApplicationDeclaresLocalNetworkUsageAndLauncher() throws {
        let destinationLocation = temporaryRoot.appendingPathComponent("World of Warcraft.app", isDirectory: true)

        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: "true",
            launcherExecutableLocation: try makeStandInLauncherExecutable()
        )

        let propertyList = try readInformationPropertyList(of: destinationLocation)
        XCTAssertEqual(propertyList["CFBundleExecutable"] as? String, "launcher")
        XCTAssertEqual(propertyList["CFBundleIdentifier"] as? String, "com.wowsilicon.launcher.World-of-Warcraft")
        XCTAssertEqual(propertyList["CFBundleName"] as? String, "World of Warcraft")
        XCTAssertEqual(propertyList["LSUIElement"] as? Bool, true)
        XCTAssertEqual(
            propertyList["NSLocalNetworkUsageDescription"] as? String,
            AppExportService.localNetworkUsageDescription
        )
        XCTAssertTrue(FileManager.default.isExecutableFile(
            atPath: destinationLocation.appendingPathComponent("Contents/MacOS/launcher").path
        ))
    }

    func testExportedApplicationHasValidSignature() throws {
        let destinationLocation = temporaryRoot.appendingPathComponent("Signed.app", isDirectory: true)

        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: "true",
            launcherExecutableLocation: try makeStandInLauncherExecutable()
        )

        let verification = try ProcessRunner.run(
            executablePath: "/usr/bin/codesign",
            arguments: ["--verify", "--strict", destinationLocation.path],
            timeout: 60
        )
        XCTAssertEqual(verification.exitCode, 0, verification.combinedOutput)
    }

    func testExportedLaunchScriptWaitsForBackgroundedGameAndIsOwnerOnly() throws {
        let destinationLocation = temporaryRoot.appendingPathComponent("Script.app", isDirectory: true)
        let shellScript = "( sleep 0 ) &"

        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: shellScript,
            launcherExecutableLocation: try makeStandInLauncherExecutable()
        )

        let launchScriptLocation = destinationLocation.appendingPathComponent("Contents/Resources/launch.zsh")
        XCTAssertEqual(try String(contentsOf: launchScriptLocation, encoding: .utf8), shellScript + "\nwait\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: launchScriptLocation.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testExportedLaunchScriptContainsGameArguments() throws {
        var version = try makeLaunchableVersion()
        version.settings.gameArguments = "-login \"NAME\" -password \"it's secret\""
        let shellScript = try LaunchService.shared.shortcutShellScript(for: version)
        let destinationLocation = temporaryRoot.appendingPathComponent("Arguments.app", isDirectory: true)

        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: shellScript,
            launcherExecutableLocation: try makeStandInLauncherExecutable()
        )

        let launchScript = try String(
            contentsOf: destinationLocation.appendingPathComponent("Contents/Resources/launch.zsh"),
            encoding: .utf8
        )
        XCTAssertTrue(launchScript.contains("'-login' 'NAME' '-password' 'it'\\''s secret'"))
    }

    func testExportedLaunchScriptWithoutGameArgumentsEndsAtExecutable() throws {
        let version = try makeLaunchableVersion()
        let shellScript = try LaunchService.shared.shortcutShellScript(for: version)
        let destinationLocation = temporaryRoot.appendingPathComponent("NoArguments.app", isDirectory: true)

        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: shellScript,
            launcherExecutableLocation: try makeStandInLauncherExecutable()
        )

        let launchScript = try String(
            contentsOf: destinationLocation.appendingPathComponent("Contents/Resources/launch.zsh"),
            encoding: .utf8
        )
        XCTAssertTrue(launchScript.contains("Game.exe'\n)"))
    }

    func testExportReplacesExistingApplication() throws {
        let destinationLocation = temporaryRoot.appendingPathComponent("Existing.app", isDirectory: true)
        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: "print -r -- first",
            launcherExecutableLocation: try makeStandInLauncherExecutable()
        )
        let leftoverLocation = destinationLocation.appendingPathComponent("Contents/Resources/leftover")
        XCTAssertTrue(FileManager.default.createFile(atPath: leftoverLocation.path, contents: Data()))

        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: "print -r -- second",
            launcherExecutableLocation: try makeStandInLauncherExecutable()
        )

        let launchScript = try String(
            contentsOf: destinationLocation.appendingPathComponent("Contents/Resources/launch.zsh"),
            encoding: .utf8
        )
        XCTAssertEqual(launchScript, "print -r -- second\nwait\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftoverLocation.path))
        let verification = try ProcessRunner.run(
            executablePath: "/usr/bin/codesign",
            arguments: ["--verify", "--strict", destinationLocation.path],
            timeout: 60
        )
        XCTAssertEqual(verification.exitCode, 0, verification.combinedOutput)
    }

    func testExportFailsWithoutLauncher() {
        let destinationLocation = temporaryRoot.appendingPathComponent("NoLauncher.app", isDirectory: true)

        XCTAssertThrowsError(try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: "true",
            launcherExecutableLocation: nil
        )) { error in
            guard case AppExportError.launcherMissing = error else {
                return XCTFail("Expected launcherMissing, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationLocation.path))
    }

    func testExportCopiesIconLocatedNextToLauncher() throws {
        let launcherExecutableLocation = try makeStandInLauncherExecutable()
        let iconSourceLocation = launcherExecutableLocation
            .deletingLastPathComponent()
            .appendingPathComponent(AppExportService.applicationIconFileName)
        try Data("icon".utf8).write(to: iconSourceLocation)
        let destinationLocation = temporaryRoot.appendingPathComponent("Icon.app", isDirectory: true)

        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: "true",
            launcherExecutableLocation: launcherExecutableLocation
        )

        let propertyList = try readInformationPropertyList(of: destinationLocation)
        XCTAssertEqual(propertyList["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(
            try Data(contentsOf: destinationLocation.appendingPathComponent("Contents/Resources/AppIcon.icns")),
            Data("icon".utf8)
        )
    }

    func testExportWithoutIconOmitsIconKey() throws {
        let destinationLocation = temporaryRoot.appendingPathComponent("NoIcon.app", isDirectory: true)

        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: "true",
            launcherExecutableLocation: try makeStandInLauncherExecutable()
        )

        let propertyList = try readInformationPropertyList(of: destinationLocation)
        XCTAssertNil(propertyList["CFBundleIconFile"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destinationLocation.appendingPathComponent("Contents/Resources/AppIcon.icns").path
        ))
    }

    func testBundleIdentifierReplacesUnsupportedCharacters() {
        XCTAssertEqual(
            AppExportService.bundleIdentifier(forApplicationName: "WoW 3.3.5a (WotLK)"),
            "com.wowsilicon.launcher.WoW-3-3-5a--WotLK"
        )
        XCTAssertEqual(
            AppExportService.bundleIdentifier(forApplicationName: "…"),
            "com.wowsilicon.launcher.World-of-Warcraft"
        )
    }

    // Runs only when WOWSILICON_APP_LAUNCHER_PATH points at a launcher built by `make app_launcher`.
    func testExportedLauncherRunsLaunchScript() throws {
        guard let launcherExecutableLocation = AppExportService.launcherExecutableLocation(resourceLocation: nil) else {
            throw XCTSkip("Set \(AppExportService.launcherEnvironmentOverride) to the built app launcher.")
        }
        let markerLocation = temporaryRoot.appendingPathComponent("launched", isDirectory: false)
        let destinationLocation = temporaryRoot.appendingPathComponent("Runs.app", isDirectory: true)

        try AppExportService.createLaunchApplication(
            at: destinationLocation,
            shellScript: "( print -r -- launched > \(LaunchService.shared.shellQuote(markerLocation.path)) ) &",
            launcherExecutableLocation: launcherExecutableLocation
        )

        let result = try ProcessRunner.run(
            executablePath: destinationLocation.appendingPathComponent("Contents/MacOS/launcher").path,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
        XCTAssertEqual(try String(contentsOf: markerLocation, encoding: .utf8), "launched\n")
    }

    // Copies /usr/bin/true as a Mach-O stand-in for the launcher; codesign requires a Mach-O main
    // executable but the stand-in is never run.
    private func makeStandInLauncherExecutable() throws -> URL {
        let standInDirectory = temporaryRoot.appendingPathComponent("StandInLauncher", isDirectory: true)
        let standInLocation = standInDirectory.appendingPathComponent("launcher", isDirectory: false)
        if !FileManager.default.fileExists(atPath: standInLocation.path) {
            try FileManager.default.createDirectory(at: standInDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: standInLocation)
        }
        return standInLocation
    }

    private func readInformationPropertyList(of applicationLocation: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: applicationLocation.appendingPathComponent("Contents/Info.plist"))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
    }

    // Produces a version accepted by LaunchService.shortcutShellScript(for:) using a stand-in Wine
    // runtime and game directory under the temporary root.
    private func makeLaunchableVersion() throws -> GameVersion {
        let gameDirectory = temporaryRoot.appendingPathComponent("Game", isDirectory: true)
        let wineRoot = temporaryRoot.appendingPathComponent("Wine", isDirectory: true)
        let wineExecutable = wineRoot.appendingPathComponent("bin/wine", isDirectory: false)
        try FileManager.default.createDirectory(
            at: wineExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: wineExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wineExecutable.path)

        let environmentKey = BundledWineRuntime.environmentOverride
        let previousEnvironmentValue = ProcessInfo.processInfo.environment[environmentKey]
        setenv(environmentKey, wineRoot.path, 1)
        addTeardownBlock {
            if let previousEnvironmentValue {
                setenv(environmentKey, previousEnvironmentValue, 1)
            } else {
                unsetenv(environmentKey)
            }
        }

        let gameExecutable = gameDirectory.appendingPathComponent("Game.exe")
        XCTAssertTrue(FileManager.default.createFile(atPath: gameExecutable.path, contents: Data()))
        var version = VersionManager.genericD3D9Template
        version.gamePath = gameExecutable.path
        version.executableName = gameExecutable.lastPathComponent
        version.settings.x87Backend = .disabled
        version.settings.autoDeleteWdb = false
        try PatchService.applyGamePatch(for: version)
        return version
    }
}
