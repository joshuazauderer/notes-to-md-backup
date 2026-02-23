import SwiftUI

struct FolderPickerView: View {
    let libraryState: LibraryLoadState
    @Binding var selectedFolderIDs: Set<String>

    var body: some View {
        Group {
            switch libraryState {
            case .idle:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Loading…")
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            case .loading:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reading Notes folders…")
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn’t read Notes")
                        .font(.headline)
                    Text(message)
                        .foregroundStyle(.secondary)
                    Text("If you denied automation permission, enable it at System Settings → Privacy & Security → Automation.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            case .loaded(let library):
                LibraryFoldersView(library: library, selectedFolderIDs: $selectedFolderIDs)
            }
        }
    }
}

private struct LibraryFoldersView: View {
    let library: NotesLibrary
    @Binding var selectedFolderIDs: Set<String>

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button("Select All") {
                        selectedFolderIDs = Set(library.allFolders.map(\.id))
                    }
                    Button("Select None") {
                        selectedFolderIDs.removeAll()
                    }
                    Spacer()
                    Text("\(selectedFolderIDs.count) folders selected")
                        .foregroundStyle(.secondary)
                }

                ForEach(library.accounts) { account in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(account.name)
                            .font(.headline)
                        FolderOutline(account: account, selectedFolderIDs: $selectedFolderIDs)
                            .padding(.leading, 8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct FolderOutline: View {
    let account: NotesAccount
    @Binding var selectedFolderIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(account.rootFolders) { folder in
                FolderRow(folder: folder, selectedFolderIDs: $selectedFolderIDs, indent: 0)
            }
        }
    }
}

private struct FolderRow: View {
    let folder: NotesFolder
    @Binding var selectedFolderIDs: Set<String>
    let indent: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { selectedFolderIDs.contains(folder.id) },
                    set: { isSelected in
                        if isSelected {
                            selectedFolderIDs.insert(folder.id)
                        } else {
                            selectedFolderIDs.remove(folder.id)
                        }
                    })
                ) {
                    Text(folder.name)
                        .lineLimit(1)
                }
                .toggleStyle(.checkbox)

                Spacer()

                Text("\(folder.noteCount) notes")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(.leading, indent)

            if !folder.children.isEmpty {
                ForEach(folder.children) { child in
                    FolderRow(folder: child, selectedFolderIDs: $selectedFolderIDs, indent: indent + 18)
                }
            }
        }
    }
}

