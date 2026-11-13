import Combine
import Foundation
import OpenLV

@MainActor
final class SessionModel: ObservableObject {
    @Published var pairingURI = ""
    @Published private(set) var state: SessionState?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var isClosing = false

    private var session: OpenLVSession?
    private var generation = UUID()
    private var connectionTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    var isActive: Bool { session != nil }

    func connect() {
        guard !isActive, !isConnecting, !isClosing else { return }

        let uri = pairingURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else { return }

        let token = UUID()
        generation = token
        errorMessage = nil
        isConnecting = true

        connectionTask = Task {
            await connect(to: uri, token: token)
        }
    }

    private func connect(to uri: String, token: UUID) async {
        do {
            let wallet = try await OpenLV.wallet(
                uri,
                info: PeerInfo(
                    identity: "com.example.openlv.ios.wallet",
                    name: "iOS Demo Wallet"
                ),
                onRequest: { request in
                    try await DemoResponder.respond(to: request)
                }
            )

            guard isCurrent(token), !Task.isCancelled else {
                try? await wallet.close()
                return
            }

            session = wallet
            await observe(wallet, token: token)
            try Task.checkCancellation()
            try await wallet.connect()
            try await wallet.waitForLink()

            let snapshot = try await wallet.state()
            guard isCurrent(token) else { return }

            state = snapshot
            isConnecting = false
        } catch {
            guard isCurrent(token) else { return }
            errorMessage = error.localizedDescription
            disconnect()
        }
    }

    func disconnect() {
        guard isActive || isConnecting else { return }

        generation = UUID()
        connectionTask?.cancel()
        stateTask?.cancel()
        connectionTask = nil
        stateTask = nil
        isConnecting = false
        state = nil

        guard let session else { return }
        self.session = nil
        isClosing = true

        Task {
            do {
                try await session.close()
            } catch {
                errorMessage = error.localizedDescription
            }
            isClosing = false
        }
    }

    private func observe(_ session: OpenLVSession, token: UUID) async {
        let states = await session.states()

        if let snapshot = try? await session.state(), isCurrent(token) {
            state = snapshot
        }

        stateTask = Task { [weak self] in
            do {
                for try await update in states {
                    guard let self, self.isCurrent(token) else { return }
                    self.state = update
                }
            } catch {
                guard let self,
                      self.isCurrent(token),
                      !(error is CancellationError)
                else {
                    return
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func isCurrent(_ token: UUID) -> Bool {
        generation == token
    }
}
