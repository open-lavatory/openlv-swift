import SwiftUI

struct ContentView: View {
    @ObservedObject var model: SessionModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Wallet") {
                    TextField("openlv:// pairing URI", text: $model.pairingURI, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(model.isActive || model.isConnecting || model.isClosing)

                    if model.isActive || model.isConnecting {
                        Button("Disconnect", role: .destructive, action: model.disconnect)
                    } else {
                        Button("Connect", action: model.connect)
                            .disabled(
                                model.isClosing
                                    || model.pairingURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                    }

                    if model.isConnecting || model.isClosing {
                        ProgressView(model.isClosing ? "Closing…" : "Connecting…")
                    }
                }

                if let state = model.state {
                    Section("Session") {
                        LabeledContent("Status", value: state.status.rawValue)
                        LabeledContent("Signaling", value: state.signaling?.rawValue ?? "—")
                        LabeledContent("Peer", value: state.peer?.name ?? "Waiting")
                    }
                }

                if let error = model.errorMessage {
                    Section("Error") {
                        Text(error).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("OpenLV Wallet")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
