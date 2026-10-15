import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Options controls that save the current launch configuration as a standalone macOS application.
// Unlike a Shortcut, a standalone application can be granted Local Network access by macOS, which
// is required to reach realm servers on a private network address.
struct ApplicationExportControls: View {
    static let defaultApplicationFileName = "World of Warcraft.app"

    @ObservedObject var viewModel: MainDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Launch App")
                .font(.headline)

            Text("Create a standalone app using the current configuration. Unlike a shortcut, it can be allowed to reach realm servers on your local network. Its settings stay frozen until you create a new app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    presentSavePanel()
                } label: {
                    Label("Create App…", systemImage: "app.badge")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canLaunch || viewModel.isApplicationExportInProgress)

                if viewModel.isApplicationExportInProgress {
                    ProgressView()
                        .controlSize(.small)
                    Text("Creating app…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let feedback = viewModel.applicationExportFeedback {
                HStack(spacing: 8) {
                    Label(
                        feedback.message,
                        systemImage: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(feedback.isError ? .red : .green)

                    if !feedback.isError, viewModel.exportedApplicationLocation != nil {
                        Button("Show in Finder") {
                            viewModel.revealExportedApplication()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func presentSavePanel() {
        let applicationsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        // NSSavePanel ignores a directoryURL that does not exist.
        try? FileManager.default.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)

        let savePanel = NSSavePanel()
        savePanel.title = "Create Launch App"
        savePanel.prompt = "Create"
        savePanel.directoryURL = applicationsDirectory
        savePanel.nameFieldStringValue = Self.defaultApplicationFileName
        savePanel.allowedContentTypes = [.applicationBundle]
        savePanel.canCreateDirectories = true
        savePanel.begin { response in
            guard response == .OK, let destinationLocation = savePanel.url else { return }
            viewModel.exportLaunchApplication(to: destinationLocation)
        }
    }
}
