import Foundation

enum AppExportError: LocalizedError {
    case launcherMissing
    case attributeRemovalFailed(String)
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .launcherMissing:
            return "The app launcher is missing from WoWSilicon. Reinstall WoWSilicon and try again."
        case .attributeRemovalFailed(let detail):
            return "macOS could not prepare the app for signing: \(detail)"
        case .signingFailed(let detail):
            return detail.isEmpty
                ? "macOS could not sign the app."
                : "macOS could not sign the app: \(detail)"
        }
    }
}

// Builds standalone macOS application bundles that run a launch script with /bin/zsh.
// The bundle's executable is a native launcher, so macOS treats the bundle as the responsible
// application for the game process, including for Local Network privacy prompts.
enum AppExportService {
    static let launcherEnvironmentOverride = "WOWSILICON_APP_LAUNCHER_PATH"
    static let launcherResourceSubdirectory = "AppLauncher"
    static let launcherExecutableName = "launcher"
    static let launchScriptName = "launch.zsh"
    static let applicationIconFileName = "AppIcon.icns"
    static let localNetworkUsageDescription =
        "Connects to World of Warcraft realm servers on your local network."

    static func launcherExecutableLocation(
        resourceLocation: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidateLocation: URL?
        if let override = environment[launcherEnvironmentOverride]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            candidateLocation = URL(fileURLWithPath: override, isDirectory: false)
        } else {
            candidateLocation = resourceLocation?
                .appendingPathComponent(launcherResourceSubdirectory, isDirectory: true)
                .appendingPathComponent(launcherExecutableName, isDirectory: false)
        }
        guard let candidateLocation, fileManager.isExecutableFile(atPath: candidateLocation.path) else {
            return nil
        }
        return candidateLocation
    }

    static func createLaunchApplication(
        at destinationLocation: URL,
        shellScript: String,
        launcherExecutableLocation: URL? = AppExportService.launcherExecutableLocation(),
        fileManager: FileManager = .default
    ) throws {
        guard let launcherExecutableLocation else {
            throw AppExportError.launcherMissing
        }

        // A staging directory on the destination's volume keeps the final move a rename.
        let stagingDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destinationLocation.deletingLastPathComponent(),
            create: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let stagedApplicationLocation = stagingDirectory
            .appendingPathComponent(destinationLocation.lastPathComponent, isDirectory: true)
        try assembleApplicationBundle(
            at: stagedApplicationLocation,
            applicationName: destinationLocation.deletingPathExtension().lastPathComponent,
            shellScript: shellScript,
            launcherExecutableLocation: launcherExecutableLocation,
            fileManager: fileManager
        )
        try removeExtendedAttributes(from: stagedApplicationLocation)
        try signAdHoc(stagedApplicationLocation)
        // NSSavePanel has already asked the user to confirm replacing an existing item.
        // replaceItemAt swaps the items on the same volume, so the destination is never left partial.
        if fileManager.fileExists(atPath: destinationLocation.path) {
            _ = try fileManager.replaceItemAt(destinationLocation, withItemAt: stagedApplicationLocation)
        } else {
            try fileManager.moveItem(at: stagedApplicationLocation, to: destinationLocation)
        }
    }

    // The launch script backgrounds the game in a subshell and returns immediately. The trailing
    // `wait` keeps the shell, and therefore the launcher process, alive until the game exits.
    static func launchScript(wrapping shellScript: String) -> String {
        shellScript + "\nwait\n"
    }

    static func bundleIdentifier(forApplicationName applicationName: String) -> String {
        // Bundle identifiers permit only ASCII letters, digits, hyphens and periods.
        let permittedCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
        )
        let identifierComponent = String(
            applicationName.unicodeScalars.map { permittedCharacters.contains($0) ? Character($0) : "-" }
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "com.wowsilicon.launcher."
            + (identifierComponent.isEmpty ? "World-of-Warcraft" : identifierComponent)
    }

    static func informationPropertyList(applicationName: String, includesIcon: Bool) -> [String: Any] {
        var propertyList: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": applicationName,
            "CFBundleExecutable": launcherExecutableName,
            "CFBundleIdentifier": bundleIdentifier(forApplicationName: applicationName),
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": applicationName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            // The launcher has no user interface; this hides its Dock icon while the game runs.
            "LSUIElement": true,
            "NSLocalNetworkUsageDescription": localNetworkUsageDescription
        ]
        if includesIcon {
            propertyList["CFBundleIconFile"] = (applicationIconFileName as NSString).deletingPathExtension
        }
        return propertyList
    }

    private static func assembleApplicationBundle(
        at applicationLocation: URL,
        applicationName: String,
        shellScript: String,
        launcherExecutableLocation: URL,
        fileManager: FileManager
    ) throws {
        let contentsDirectory = applicationLocation.appendingPathComponent("Contents", isDirectory: true)
        let executableDirectory = contentsDirectory.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesDirectory = contentsDirectory.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)

        let bundledLauncherLocation = executableDirectory
            .appendingPathComponent(launcherExecutableName, isDirectory: false)
        try fileManager.copyItem(at: launcherExecutableLocation, to: bundledLauncherLocation)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledLauncherLocation.path)

        let iconSourceLocation = launcherExecutableLocation
            .deletingLastPathComponent()
            .appendingPathComponent(applicationIconFileName, isDirectory: false)
        let includesIcon = fileManager.fileExists(atPath: iconSourceLocation.path)
        if includesIcon {
            try fileManager.copyItem(
                at: iconSourceLocation,
                to: resourcesDirectory.appendingPathComponent(applicationIconFileName, isDirectory: false)
            )
        }

        let propertyListData = try PropertyListSerialization.data(
            fromPropertyList: informationPropertyList(applicationName: applicationName, includesIcon: includesIcon),
            format: .xml,
            options: 0
        )
        try propertyListData.write(to: contentsDirectory.appendingPathComponent("Info.plist", isDirectory: false))

        let launchScriptLocation = resourcesDirectory
            .appendingPathComponent(launchScriptName, isDirectory: false)
        try Data(launchScript(wrapping: shellScript).utf8).write(to: launchScriptLocation)
        // Game arguments in the script can contain account credentials.
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: launchScriptLocation.path)
    }

    // codesign rejects bundles containing extended attributes such as Finder information, and
    // copied files carry over attributes such as com.apple.quarantine from WoWSilicon's resources.
    private static func removeExtendedAttributes(from applicationLocation: URL) throws {
        let result = try ProcessRunner.run(
            executablePath: "/usr/bin/xattr",
            arguments: ["-cr", applicationLocation.path],
            timeout: 30
        )
        guard result.exitCode == 0 else {
            throw AppExportError.attributeRemovalFailed(
                result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func signAdHoc(_ applicationLocation: URL) throws {
        let result = try ProcessRunner.run(
            executablePath: "/usr/bin/codesign",
            arguments: ["--force", "--sign", "-", applicationLocation.path],
            timeout: 60
        )
        guard result.exitCode == 0 else {
            throw AppExportError.signingFailed(
                result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
