import Foundation
import NIOCore
import NIOPosix
import NIOSSH

struct SSHResult {
    var stdout: String
    var stderr: String
    var exitStatus: Int32?
    var combined: String { stderr.isEmpty ? stdout : stdout + (stdout.isEmpty ? "" : "\n") + stderr }
}

enum SSHError: LocalizedError {
    case noKey
    case demo
    case connect(String)
    case auth
    case exec(String)

    var errorDescription: String? {
        switch self {
        case .noKey:          return "No way to log in — add a key in Tools › SSH key, or the server's password in its settings"
        case .demo:           return "Sample fleet — turn off Demo data in Settings to run this on a real relay."
        case .connect(let m): return "Could not connect: \(m)"
        case .auth:           return "Login refused — check the key (authorized_keys) or the server's password"
        case .exec(let m):    return "Command failed: \(m)"
        }
    }
}

/// Connects to a relay over SSH and runs one command (Apple swift-nio-ssh).
/// Command execution only — no interactive shell.
actor SSHRunner {
    static let shared = SSHRunner()
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)

    func run(_ command: String, on server: Server, timeout: TimeInterval = 25, usePassword: Bool = true) async throws -> SSHResult {
        // Demo relays carry RFC 5737 documentation addresses that nothing
        // answers. Six tool screens can reach this, and without the guard each
        // one fires a real connection and sits for the whole timeout before
        // failing — the demo fleet is exactly what a first-time user and App
        // Review tap through, so it has to answer at once and say why.
        // UserDefaults rather than FleetStore: same key FleetStore reads and
        // writes, and it keeps the SSH layer from reaching into the UI store.
        guard !UserDefaults.standard.bool(forKey: "demoMode") else { throw SSHError.demo }
        let pem = SSHKeyStore.pem
        let key = pem.isEmpty ? nil : try OpenSSHKey.ed25519(fromPEM: pem)
        let password = usePassword ? SSHKeyStore.password(for: server.name) : ""
        guard key != nil || !password.isEmpty else { throw SSHError.noKey }
        let user = server.sshUser.isEmpty ? "root" : server.sshUser
        return try await execute(command, on: server,
                                 auth: LoginAuth(username: user, key: key, password: password), timeout: timeout)
    }

    /// Password-only login with a password that is not stored: putting this
    /// phone's public key on a server during "Install on a server".
    func run(_ command: String, on server: Server, password: String, timeout: TimeInterval = 25) async throws -> SSHResult {
        guard !UserDefaults.standard.bool(forKey: "demoMode") else { throw SSHError.demo }
        let user = server.sshUser.isEmpty ? "root" : server.sshUser
        return try await execute(command, on: server, auth: LoginAuth(username: user, key: nil, password: password), timeout: timeout)
    }

    private func execute(_ command: String, on server: Server,
                         auth: NIOSSHClientUserAuthenticationDelegate,
                         timeout: TimeInterval) async throws -> SSHResult {
        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(12))
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    NIOSSHHandler(
                        role: .client(.init(userAuthDelegate: auth, serverAuthDelegate: AcceptAllHostKeys())),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                ])
            }

        // One retry, and only on the connect. Measured across a 143-relay fleet
        // on 2026-09-07/08: eighteen SSH attempts failed to connect during bulk
        // work and every single one succeeded when tried again a moment later.
        // The agent path has retried transient failures for a while
        // (AgentClient); SSH had one shot, so a relay could be called stale or
        // offline over a hiccup that a second attempt would have cleared.
        //
        // Deliberately NOT retried: authentication (repeating a bad key is what
        // gets an address banned by fail2ban) and anything after the connection
        // is up, since the command may already have run — these are used for
        // fix commands, not only for reads.
        let channel: Channel
        do {
            channel = try await connect(bootstrap, to: server)
        } catch {
            try? await Task.sleep(nanoseconds: 600_000_000)
            do {
                channel = try await connect(bootstrap, to: server)
            } catch {
                throw SSHError.connect(Self.describe(error))
            }
        }
        // Fire-and-forget close. `channel.close().wait()` BLOCKS the calling
        // thread, and these run on Swift concurrency's cooperative pool, which
        // has only a handful of threads. One SSH at a time (the Tools screens)
        // got away with it; the poll loop's SSH fallback can start several at
        // once, and blocking that many pool threads hangs the app until the
        // watchdog kills it — the SIGKILL seen on device 2026-09-03.
        defer { channel.close(promise: nil) }

        let collector = OutputCollector()
        do {
            let child: Channel = try await withCheckedThrowingContinuation { cont in
                channel.pipeline.handler(type: NIOSSHHandler.self).whenComplete { res in
                    switch res {
                    case .failure(let e): cont.resume(throwing: e)
                    case .success(let handler):
                        let promise = channel.eventLoop.makePromise(of: Channel.self)
                        handler.createChannel(promise) { child, _ in
                            child.pipeline.addHandlers([
                                SSHCommandHandler(command: command, collector: collector)
                            ])
                        }
                        promise.futureResult.whenComplete { cont.resume(with: $0) }
                    }
                }
            }
            // Wait until the channel closes (the command finished), capped by `timeout`.
            try await withThrowingTaskGroup(of: Void.self) { g in
                g.addTask { try await child.closeFuture.get() }
                g.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw SSHError.exec("timed out after \(Int(timeout))s")
                }
                try await g.next()
                g.cancelAll()
            }
        } catch let e as SSHError {
            throw e
        } catch {
            let m = String(describing: error)
            if m.localizedCaseInsensitiveContains("authentication") { throw SSHError.auth }
            throw SSHError.exec(Self.describe(error))
        }

        return collector.result()
    }

    private func connect(_ bootstrap: ClientBootstrap, to server: Server) async throws -> Channel {
        try await bootstrap.connect(host: server.host, port: server.sshPort).get()
    }

    /// A description that is English wherever the phone is.
    ///
    /// `localizedDescription` hands back Foundation's translation of the system
    /// error, so a Turkish phone logged "İşlem tamamlanamadı" and a German one
    /// would log its own. The rest of the app is English everywhere — which is
    /// what the App Store listing and the review notes both state — so a
    /// translated string leaking out of the network layer breaks that promise
    /// and makes the activity log useless to anyone reading it later.
    static func describe(_ error: Error) -> String {
        let raw = String(describing: error)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return raw.count > 160 ? String(raw.prefix(160)) + "…" : raw
    }
}

// MARK: - Authentication

private final class AcceptAllHostKeys: NIOSSHClientServerAuthenticationDelegate {
    // Relay host keys are not stable (reinstalls, multi-IP boxes). Identity is
    // proven by the private key; desktop RelayPulse also uses
    // StrictHostKeyChecking=accept-new.
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

/// Key first, then the server's password — the order `ssh` itself uses, so a
/// server that has both behaves as it does on the desktop. Each is offered
/// once: a second try with the same wrong password only feeds fail2ban.
/// Servers that allow passwords solely through keyboard-interactive (PAM) are
/// not reachable by password — swift-nio-ssh does not implement that method —
/// and fail as .auth.
private final class LoginAuth: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private var key: NIOSSHPrivateKey?
    private var password: String?

    init(username: String, key: NIOSSHPrivateKey?, password: String) {
        self.username = username
        self.key = key
        self.password = password.isEmpty ? nil : password
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        if let k = key, availableMethods.contains(.publicKey) {
            key = nil
            nextChallengePromise.succeed(.init(username: username, serviceName: "", offer: .privateKey(.init(privateKey: k))))
        } else if let pw = password, availableMethods.contains(.password) {
            password = nil
            nextChallengePromise.succeed(.init(username: username, serviceName: "", offer: .password(.init(password: pw))))
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

// MARK: - Command channel

/// A lock, not an actor. `channelRead` fires once per chunk on the channel's
/// event loop; hopping each chunk onto an actor with its own `Task` gives up
/// both ordering and timing. Separate tasks are not FIFO, so a large reply
/// (`journalctl`, an anonrc) could be reassembled with its chunks swapped, and
/// `result()` runs as soon as the channel closes — while those tasks may still
/// be queued, silently truncating the output. Appending under a lock keeps the
/// event loop's own order and finishes before the read.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    private var status: Int32?

    func appendOut(_ d: Data) { lock.lock(); out.append(d); lock.unlock() }
    func appendErr(_ d: Data) { lock.lock(); err.append(d); lock.unlock() }
    func setStatus(_ s: Int32) { lock.lock(); status = s; lock.unlock() }
    func result() -> SSHResult {
        lock.lock()
        defer { lock.unlock() }
        return SSHResult(stdout: String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                         stderr: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                         exitStatus: status)
    }
}

private final class SSHCommandHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let command: String
    private let collector: OutputCollector

    init(command: String, collector: OutputCollector) {
        self.command = command
        self.collector = collector
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in
            context.close(promise: nil)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        let req = SSHChannelRequestEvent.ExecRequest(command: command, wantReply: false)
        context.triggerUserOutboundEvent(req, promise: nil)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let payload = unwrapInboundIn(data)
        guard case .byteBuffer(let buf) = payload.data else { return }
        let bytes = Data(buf.readableBytesView)
        if payload.type == .stdErr { collector.appendErr(bytes) } else { collector.appendOut(bytes) }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let status = event as? SSHChannelRequestEvent.ExitStatus {
            collector.setStatus(Int32(status.exitStatus))
        }
        context.fireUserInboundEventTriggered(event)
    }
}
