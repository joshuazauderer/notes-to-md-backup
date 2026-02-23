import SwiftUI

struct ExportProgressView: View {
    let state: ExportRunState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.isRunning {
                ProgressView(value: state.progressFraction) {
                    Text(state.headline)
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)

                HStack {
                    Text(state.detail)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.notesProcessed)/\(max(state.notesTotal, 1)) notes")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else if let lastResult = state.lastResultMessage {
                Text(lastResult)
                    .foregroundStyle(state.lastResultWasError ? .red : .secondary)
                    .font(.callout)
            } else {
                Text("Ready.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            DisclosureGroup("Logs") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(state.logs.indices, id: \.self) { idx in
                            Text(state.logs[idx])
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 160)
                .border(.separator)
            }
        }
    }
}

