import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @AppStorage("useMockNotes") private var useMockNotes: Bool = false

    var body: some View {
        Form {
            Section("Development") {
                Toggle("Mock Notes mode (no Notes permissions)", isOn: $useMockNotes)
                    .onChange(of: useMockNotes) { _ in
                        appModel.reloadLibrary()
                    }
                Text("When enabled, the app uses an internal mock library for UI/testing.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(16)
        .frame(width: 520)
    }
}

