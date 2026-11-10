import Combine
import Foundation
import OpenLV

@MainActor
final class SessionModel: ObservableObject {
    enum Role: String, CaseIterable, Identifiable {
        case dapp = "dApp", wallet = "Wallet"
        var id: Self { self }
    }

    struct Event: Identifiable {
        let id = UUID()
        let date = Date()
        let title: String
        let detail: String
    }

    @Published var role: Role = .dapp
    @Published var walletURI = ""
    @Published var requestJSON = SessionModel.chainIDRequest
    @Published var responseTimeout = 10
    @Published private(set) var pairingURI = ""
    @Published private(set) var state: SessionState?
    @Published private(set) var demoWalletState: SessionState?
    @Published private(set) var events: [Event] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var isPairing = false
    @Published private(set) var hasDemoWallet = false
    @Published private(set) var isSending = false
    @Published private(set) var isClosing = false

    static let chainIDRequest = """
    {"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}
    """
    static let echoRequest = """
    {"jsonrpc":"2.0","id":2,"method":"demo_echo","params":["Hello from Swift",42,true]}
    """
    static let slowRequest = """
    {"jsonrpc":"2.0","id":3,"method":"demo_delay","params":[]}
    """

    private var session: OpenLVSession?
    private var demoWallet: OpenLVSession?
    private var generation = UUID()
    private var connectionTask: Task<Void, Never>?
    private var pairingTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var demoStateTask: Task<Void, Never>?

    var canSend: Bool { state?.status == .connected && !isSending && !isClosing }
    var canPairDemoWallet: Bool {
        role == .dapp && isActive && !isStarting && !isClosing && !hasDemoWallet
            && !isPairing && state?.status != .connected
    }

    func start() {
        guard !isActive, !isStarting, !isClosing else { return }
        let uri = walletURI.trimmingCharacters(in: .whitespacesAndNewlines)
        if role == .wallet {
            do { _ = try OpenLV.parseURI(uri) }
            catch { report(error); return }
        }
        let selectedRole = role
        let token = UUID()
        generation = token
        errorMessage = nil
        state = nil
        demoWalletState = nil
        isStarting = true
        connectionTask = Task {
            do {
                let created: OpenLVSession
                if selectedRole == .dapp {
                    created = try await OpenLV.dapp(options: DappOptions(
                        info: PeerInfo(identity: "com.example.openlv.ios.dapp", name: "iOS Demo dApp")
                    ), onRequest: handler(label: "dApp", token: token))
                } else {
                    created = try await OpenLV.wallet(uri,
                        info: PeerInfo(identity: "com.example.openlv.ios.wallet", name: "iOS Demo Wallet"),
                        onRequest: handler(label: "Wallet", token: token))
                }
                guard generation == token, !Task.isCancelled else {
                    try? await created.close()
                    return
                }
                session = created
                isActive = true
                pairingURI = selectedRole == .dapp ? created.uri : ""
                await observe(created, demo: false, token: token)
                try Task.checkCancellation()
                try await created.connect()
                guard generation == token else { return }
                isStarting = false
                log("Signaling started", selectedRole == .dapp
                    ? "Waiting for a peer. Pair on another device or use the demo wallet."
                    : "Waiting for the dApp to complete linking.")
                try await created.waitForLink()
                guard generation == token else { return }
                state = try await created.state()
                log("Peer linked", state?.peer?.name ?? selectedRole.rawValue)
            } catch {
                guard generation == token else { return }
                report(error)
                disconnect()
            }
        }
    }

    /// A real second native session, using the same signaling and WebRTC path as a remote wallet.
    func pairDemoWallet() {
        guard canPairDemoWallet, let session else { return }
        let token = generation
        errorMessage = nil
        isPairing = true
        pairingTask = Task {
            var created: OpenLVSession?
            do {
                let wallet = try await OpenLV.wallet(session.uri,
                    info: PeerInfo(identity: "com.example.openlv.ios.demo-wallet", name: "In-app Demo Wallet"),
                    onRequest: handler(label: "Demo wallet", token: token))
                created = wallet
                guard generation == token, !Task.isCancelled else {
                    try? await wallet.close()
                    return
                }
                demoWallet = wallet
                hasDemoWallet = true
                await observe(wallet, demo: true, token: token)
                try Task.checkCancellation()
                try await wallet.connect()
                try await wallet.waitForLink()
                guard generation == token else { return }
                demoWalletState = try await wallet.state()
                isPairing = false
                log("Demo wallet linked", "Requests can now travel in either direction.")
            } catch {
                if let created { try? await created.close() }
                guard generation == token else { return }
                demoStateTask?.cancel()
                demoWallet = nil
                hasDemoWallet = false
                isPairing = false
                report(error)
            }
        }
    }

    func send(fromDemoWallet: Bool = false) {
        guard canSend, let sender = fromDemoWallet ? demoWallet : session else { return }
        let message: JSONValue
        do { message = try JSONDecoder().decode(JSONValue.self, from: Data(requestJSON.utf8)) }
        catch { report(error); return }
        let token = generation
        let label = fromDemoWallet ? "Demo wallet" : role.rawValue
        let timeout = RequestTimeouts(acknowledgement: .seconds(10), response: .seconds(responseTimeout))
        errorMessage = nil
        isSending = true
        log("\(label) → request", Self.pretty(message))
        requestTask = Task {
            defer { if generation == token { isSending = false } }
            do {
                let response = try await sender.send(message, timeouts: timeout)
                guard generation == token else { return }
                log("\(label) ← response", Self.pretty(response))
            } catch {
                guard generation == token else { return }
                if error is CancellationError { log("Request cancelled", "The session is still open.") }
                else { report(error) }
            }
        }
    }

    func cancelRequest() { requestTask?.cancel() }

    /// Called explicitly by Disconnect and when the scene enters the background.
    func disconnect() {
        guard !isClosing, isActive || isStarting else { return }
        generation = UUID() // Ignore late state updates and handler replies from the previous session.
        isClosing = true
        let tasks = [connectionTask, pairingTask, requestTask, stateTask, demoStateTask].compactMap { $0 }
        tasks.forEach { $0.cancel() }
        let sessions = [session, demoWallet].compactMap { $0 }
        connectionTask = nil
        pairingTask = nil
        requestTask = nil
        stateTask = nil
        demoStateTask = nil
        session = nil
        demoWallet = nil
        pairingURI = ""
        isActive = false
        isStarting = false
        isPairing = false
        hasDemoWallet = false
        isSending = false
        Task {
            for session in sessions {
                do { try await session.close() }
                catch { report(error) }
            }
            // Creation can finish after cancellation; those tasks close their newly created sessions.
            for task in tasks { await task.value }
            state = nil
            demoWalletState = nil
            isClosing = false
            log("Sessions closed", "State subscriptions and pending operations have stopped.")
        }
    }

    func clearLog() { events.removeAll() }

    private func observe(_ session: OpenLVSession, demo: Bool, token: UUID) async {
        let states = await session.states() // Subscribe before connect so early changes are retained.
        if let snapshot = try? await session.state(), generation == token {
            if demo { demoWalletState = snapshot } else { state = snapshot }
        }
        guard generation == token, !Task.isCancelled else { return }
        let observer = Task {
            do {
                for try await update in states {
                    guard generation == token, !Task.isCancelled else { return }
                    if demo { demoWalletState = update } else { state = update }
                    log("\(demo ? "Demo wallet" : role.rawValue) state", Self.describe(update))
                }
                if generation == token { log("State stream ended", demo ? "Demo wallet" : role.rawValue) }
            } catch {
                if generation == token, !(error is CancellationError) { report(error) }
            }
        }
        if demo { demoStateTask = observer } else { stateTask = observer }
    }

    private func handler(label: String, token: UUID) -> RequestHandler {
        { [weak self] request in
            await self?.recordRequest(request, label: label, token: token)
            let response = try await DemoResponder.respond(to: request)
            await self?.recordResponse(response, label: label, token: token)
            return response
        }
    }

    private func recordRequest(_ request: JSONValue, label: String, token: UUID) {
        guard generation == token else { return }
        log("\(label) received", Self.pretty(request))
    }

    private func recordResponse(_ response: JSONValue, label: String, token: UUID) {
        guard generation == token else { return }
        log("\(label) replied", Self.pretty(response))
    }

    private func report(_ error: any Error) {
        let description = (error as? OpenLVError).map { "\($0.kind.rawValue): \($0.message)" }
            ?? error.localizedDescription
        errorMessage = description
        log("Error", description)
    }

    private func log(_ title: String, _ detail: String) {
        events.insert(Event(title: title, detail: detail), at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
    }

    private static func describe(_ state: SessionState) -> String {
        [state.status.rawValue, state.signaling?.rawValue, state.peer?.name, state.error]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private static func pretty(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "Unable to encode JSON" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Test data only: no keys, accounts, signing, or transaction submission.
enum DemoResponder {
    static func respond(to request: JSONValue) async throws -> JSONValue {
        let result: JSONValue
        switch request["method"]?.stringValue {
        case "eth_chainId": result = "0x1"
        case "demo_echo": result = request["params"] ?? .null
        case "demo_delay":
            try await Task.sleep(for: .seconds(5))
            result = "Delayed for five seconds"
        default:
            return [
                "jsonrpc": "2.0", "id": request["id"] ?? .null,
                "error": ["code": -32601, "message": "Method not found"],
            ]
        }
        return ["jsonrpc": "2.0", "id": request["id"] ?? .null, "result": result]
    }
}
