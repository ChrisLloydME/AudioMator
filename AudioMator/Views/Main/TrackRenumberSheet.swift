import SwiftUI

struct TrackRenumberSheet: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState

    @Binding var isPresented: Bool
    @Binding var trackRenumberOptions: TrackRenumberOptions
    @Binding var trackRenumberStartText: String
    @Binding var isTrackRenumberRunning: Bool
    @Binding var trackRenumberResult: TrackRenumberResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Renumber Track Numbers")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if isTrackRenumberRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Rewrite TRCK based on the middle list order. If you have a selection, only selected items will be renumbered (in their ordered appearance).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Direction", selection: $trackRenumberOptions.direction) {
                        Text("Ascending").tag(TrackRenumberDirection.ascending)
                        Text("Descending").tag(TrackRenumberDirection.descending)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Start number")
                        Spacer()
                        TextField("1", text: $trackRenumberStartText)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                            .disabled(isTrackRenumberRunning)
                    }

                    Toggle("Pad with zeros", isOn: $trackRenumberOptions.padWithZeros)
                        .disabled(isTrackRenumberRunning)
                }
                .padding(.vertical, 2)
            } label: {
                Text("Options")
            }

            if trackRenumberResult.totalTargets > 0 ||
                trackRenumberResult.failed > 0 ||
                trackRenumberResult.skippedUnsupported > 0 {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Targets: \(trackRenumberResult.totalTargets)")
                        Text("Succeeded: \(trackRenumberResult.succeeded)")
                        Text("Skipped (unsupported): \(trackRenumberResult.skippedUnsupported)")
                        Text("Failed: \(trackRenumberResult.failed)")

                        if !trackRenumberResult.failures.isEmpty {
                            Divider()
                            Text("Failures")
                                .font(.headline)

                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(trackRenumberResult.failures) { failure in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(failure.fileName)
                                                .font(.system(.body, design: .monospaced))
                                            Text(failure.reason)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 4)

                                        Divider()
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Result")
                }
            }

            Spacer()

            HStack {
                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isTrackRenumberRunning)

                Button("Apply") {
                    applyTrackRenumber()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isTrackRenumberRunning || viewModel.files.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }

    private func applyTrackRenumber() {
        let parsed = Int(trackRenumberStartText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        trackRenumberOptions.startNumber = max(0, parsed)

        let orderedIDs: [AudioFile.ID] = state.customOrder.isEmpty
            ? viewModel.files.map { $0.id }
            : state.customOrder

        let selected = state.selectedAudioIDs

        isTrackRenumberRunning = true
        trackRenumberResult = .empty

        Task {
            let result = await viewModel.renumberTrackNumbers(
                orderedIDs: orderedIDs,
                selectedIDs: selected,
                options: trackRenumberOptions
            )

            await MainActor.run {
                trackRenumberResult = result
                isTrackRenumberRunning = false
            }
        }
    }
}
