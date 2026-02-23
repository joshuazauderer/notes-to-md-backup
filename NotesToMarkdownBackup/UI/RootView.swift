import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes → Markdown Backup")
                            .font(.title2.weight(.semibold))
                        Text("Select folders, then export a ZIP.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        appModel.testNotesConnection()
                    } label: {
                        if appModel.isTestingNotesConnection {
                            Text("Testing…")
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(appModel.isBusy || appModel.isTestingNotesConnection)
                    Button("Reload") {
                        appModel.reloadLibrary()
                    }
                    .disabled(appModel.isBusy)

                    Button("Permissions…") {
                        appModel.presentPermissionsSheet()
                    }
                    .buttonStyle(.link)
                    .disabled(appModel.isBusy)
                }

                Divider()

                FolderPickerView(
                    libraryState: appModel.libraryState,
                    selectedFolderIDs: $appModel.selectedFolderIDs
                )
                .frame(minHeight: 300)

                Divider()

                ExportControlsView()

                DisclosureGroup("Diagnostics") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(appModel.diagnosticsLines.indices, id: \.self) { idx in
                                Text(appModel.diagnosticsLines[idx])
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 140)
                    .border(.separator)
                }
            }
            .padding(16)
            .navigationTitle("")
            .toolbar(.hidden)
        }
        .frame(minWidth: 820, minHeight: 640)
        .task {
            appModel.reloadLibrary()
        }
        .sheet(isPresented: $appModel.showPermissionsSheet, onDismiss: {
            appModel.markPermissionsSheetSeen()
        }) {
            PermissionsRequiredView()
                .environmentObject(appModel)
        }
        .alert(item: $appModel.appAlert) { alert in
            switch alert {
            case .info(_, let title, let message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .exportSucceeded(_, let zipURL):
                return Alert(
                    title: Text("Export completed"),
                    message: Text("Created:\n\(zipURL.path(percentEncoded: false))"),
                    primaryButton: .default(Text("Show in Finder"), action: {
                        NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                    }),
                    secondaryButton: .default(Text("OK"))
                )
            }
        }
    }
}

private struct PermissionsRequiredView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var automationStatus: String = "Checking…"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions Required")
                .font(.title2.weight(.semibold))

            Text("To export your notes, this app needs permission to control Notes (Automation). You’ll be prompted the first time you connect.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Automation (Notes)")
                    .font(.headline)
                Text(automationStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Request Automation Permission") {
                    let status = AutomationPermission.requestNotesPermission(askUserIfNeeded: true)
                    automationStatus = "Status: \(AutomationPermission.describe(status))"
                    appModel.diag("permissionsSheet: AEDeterminePermissionToAutomateTarget => \(AutomationPermission.describe(status))")
                }

                Button("Open Automation Settings") {
                    SystemSettingsOpener.openAutomationSettings()
                }

                Spacer()

                Button("Continue") {
                    appModel.showPermissionsSheet = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Text("If you don’t see a prompt, open System Settings → Privacy & Security → Automation and enable this app for Notes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("File Access")
                .font(.headline)
            Text("When you choose a ZIP destination, macOS will grant this app access to write there. No additional permissions are required.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            let status = AutomationPermission.requestNotesPermission(askUserIfNeeded: false)
            automationStatus = "Status: \(AutomationPermission.describe(status))"
            appModel.diag("permissionsSheet: initial AEDeterminePermissionToAutomateTarget => \(AutomationPermission.describe(status))")
        }
    }
}

private enum SystemSettingsOpener {
    static func openAutomationSettings() {
        // Best-effort deep link. If it fails, we still open System Settings.
        let urls: [URL] = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security"),
            URL(string: "x-apple.systempreferences:")
        ].compactMap { $0 }

        for url in urls {
            if NSWorkspace.shared.open(url) { return }
        }
    }
}

private struct ExportControlsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    private var exportDisabledReason: String? {
        if appModel.exportState.isRunning { return "Export in progress…" }
        if appModel.libraryState.library == nil { return "Load folders first." }
        if appModel.destinationURL == nil { return "Choose a ZIP destination to enable export." }
        if appModel.selectedFolderIDs.isEmpty { return "Select one or more folders to enable export." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    appModel.chooseDestination()
                } label: {
                    Text("Choose ZIP Destination…")
                }
                .disabled(appModel.isBusy)

                if let url = appModel.destinationURL {
                    Text(url.path(percentEncoded: false))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No destination selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if appModel.exportState.isRunning {
                    Button("Cancel") { appModel.cancelExport() }
                } else {
                    Button("Export ZIP") { appModel.startExport() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!appModel.canExport)
                }
            }

            if !appModel.canExport, let exportDisabledReason {
                Text(exportDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ExportProgressView(state: appModel.exportState)
        }
    }
}

