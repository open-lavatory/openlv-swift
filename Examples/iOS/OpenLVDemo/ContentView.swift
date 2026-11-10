import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var model: SessionModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Exercise real OpenLV signaling and WebRTC with another device or an in-app demo wallet.")
                    Text("Demo responses only. This app does not sign transactions or manage accounts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                connectionSection
                if !model.pairingURI.isEmpty { pairingSection }
                if model.isActive { stateSection }
                requestSection
                if let error = model.errorMessage {
                    Section("Last error") {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                logSection
            }
            .navigationTitle("OpenLV Demo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var connectionSection: some View {
        Section {
            Picker("Role", selection: $model.role) {
                ForEach(SessionModel.Role.allCases) { role in Text(role.rawValue).tag(role) }
            }
            .pickerStyle(.segmented)
            .disabled(model.isActive || model.isStarting || model.isClosing)

            if model.role == .wallet {
                TextField("Paste openlv:// pairing URI", text: $model.walletURI, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(model.isActive || model.isStarting || model.isClosing)
                    .accessibilityLabel("Wallet pairing URI")
            }

            if model.isActive || model.isStarting {
                Button("Disconnect", role: .destructive) { model.disconnect() }
            } else {
                Button(model.role == .dapp ? "Start dApp" : "Connect wallet") { model.start() }
                    .disabled(model.isClosing || (model.role == .wallet && model.walletURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            if model.isStarting || model.isClosing {
                HStack {
                    ProgressView()
                    Text(model.isClosing ? "Closing sessions…" : "Starting signaling…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Sessions close when the app enters the background. Keep both peers in the foreground during a test.")
        }
    }

    private var pairingSection: some View {
        Section {
            Text(model.pairingURI)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel("dApp pairing URI")
            HStack {
                Button {
                    UIPasteboard.general.setItems(
                        [[UIPasteboard.typeAutomatic: model.pairingURI]],
                        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)]
                    )
                } label: {
                    Label("Copy URI", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                Spacer()
                ShareLink(item: model.pairingURI) { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderless)
            }
            Button("Pair demo wallet") { model.pairDemoWallet() }
                .disabled(!model.canPairDemoWallet)
            if model.isPairing { ProgressView("Pairing demo wallet…") }
        } header: {
            Text("Pair a wallet")
        } footer: {
            Text("The URI contains the session secret. Share it only with your test peer. The demo wallet creates a second real session in this app and still requires internet access.")
        }
    }

    private var stateSection: some View {
        Section("Session state") {
            LabeledContent("Status", value: model.state?.status.rawValue ?? "created")
            LabeledContent("Signaling", value: model.state?.signaling?.rawValue ?? "—")
            LabeledContent("Peer", value: model.state?.peer?.name ?? "Waiting")
            if model.hasDemoWallet {
                LabeledContent("Demo wallet", value: model.demoWalletState?.status.rawValue ?? "created")
            }
        }
    }

    private var requestSection: some View {
        Section {
            Menu("Load sample request") {
                Button("Chain ID") { model.requestJSON = SessionModel.chainIDRequest }
                Button("Echo") { model.requestJSON = SessionModel.echoRequest }
                Button("Five-second delay") { model.requestJSON = SessionModel.slowRequest }
            }
            TextEditor(text: $model.requestJSON)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 120)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("JSON request")
            Stepper("Response timeout: \(model.responseTimeout)s", value: $model.responseTimeout, in: 1...60)
            Button("Send request") { model.send() }
                .disabled(!model.canSend)
            if model.hasDemoWallet {
                Button("Send from demo wallet") { model.send(fromDemoWallet: true) }
                    .disabled(!model.canSend || model.demoWalletState?.status != .connected)
            }
            if model.isSending {
                HStack {
                    ProgressView("Waiting for response…")
                    Spacer()
                    Button("Cancel") { model.cancelRequest() }.buttonStyle(.borderless)
                }
            }
        } header: {
            Text("JSON request")
        } footer: {
            Text("Both demo peers handle eth_chainId, demo_echo, and demo_delay (5 seconds). Other methods return JSON-RPC error −32601. Use a 1-second timeout or Cancel with the delay sample to exercise request failures.")
        }
    }

    private var logSection: some View {
        Section {
            if model.events.isEmpty {
                Text("State changes, incoming requests, and responses appear here.")
                    .foregroundStyle(.secondary)
            } else {
                Button("Clear log") { model.clearLog() }
                ForEach(model.events) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(event.title).font(.subheadline.bold())
                            Spacer()
                            Text(event.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(event.detail).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Traffic log · newest first")
        } footer: {
            Text("The latest 100 events stay in memory. Logs are cleared when the app exits.")
        }
    }
}
