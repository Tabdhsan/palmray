import Foundation
import Network

// All methods and callbacks run on the capture queue.
final class HandSender {
    let queue: DispatchQueue
    var onStatus: ((String) -> Void)?
    var browser: NWBrowser?
    var connection: NWConnection?
    var endpoints: Set<NWBrowser.Result> = []
    var ready = false
    var busy = false
    var pendingSequence: Int?
    var replyBuffer = Data()
    var enabled = false

    init(queue: DispatchQueue) { self.queue = queue }

    func start() {
        guard !enabled else { return }
        enabled = true
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_rayneohand._tcp", domain: nil), using: parameters)
        self.browser = browser
        onStatus?("Searching for Mac…")
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.endpoints = results
            self?.connect()
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .waiting(let error) = state { self?.onStatus?("Network permission or connection needed: \(error)") }
            if case .failed(let error) = state { self?.onStatus?("Discovery failed: \(error)") }
        }
        browser.start(queue: queue)
    }

    func connect() {
        guard enabled, connection == nil, let endpoint = endpoints.first?.endpoint else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        onStatus?("Connecting to Mac…")
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connection === connection else { return }
            switch state {
            case .ready:
                self.ready = true
                self.receiveAcknowledgements(connection)
                self.onStatus?("Connected to Mac test window")
            case .failed, .cancelled, .waiting:
                self.disconnect(connection)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    func disconnect(_ connection: NWConnection) {
        guard self.connection === connection else { return }
        self.connection = nil
        ready = false
        busy = false
        pendingSequence = nil
        replyBuffer.removeAll()
        connection.cancel()
        if enabled {
            onStatus?("Mac disconnected · retrying…")
            queue.asyncAfter(deadline: .now() + 2) { self.connect() }
        }
    }

    func send(_ packet: HandPacket) {
        guard ready, !busy, let connection, var data = try? JSONEncoder().encode(packet) else { return }
        data.append(10)
        busy = true
        pendingSequence = packet.sequence
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self, weak connection] in
            guard let self, let connection, self.connection === connection, self.pendingSequence == packet.sequence else { return }
            self.disconnect(connection)
        }
        connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection, self.connection === connection else { return }
            if error != nil { self.disconnect(connection) }
        })
    }

    func receiveAcknowledgements(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection, self.connection === connection else { return }
            if let data { self.replyBuffer.append(data) }
            guard self.replyBuffer.count <= 4096 else { self.disconnect(connection); return }
            while let newline = self.replyBuffer.firstIndex(of: 10) {
                let line = self.replyBuffer.prefix(upTo: newline)
                if let text = String(data: line, encoding: .utf8), let sequence = Int(text), sequence == self.pendingSequence {
                    self.pendingSequence = nil
                    self.busy = false
                }
                self.replyBuffer.removeSubrange(...newline)
            }
            if complete || error != nil { self.disconnect(connection) }
            else { self.receiveAcknowledgements(connection) }
        }
    }

    func stop() {
        enabled = false
        browser?.cancel()
        browser = nil
        endpoints = []
        if let connection { disconnect(connection) }
        onStatus?("Mac link stopped")
    }
}
