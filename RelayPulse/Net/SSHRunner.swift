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
    case connect(String)
    case auth
    case exec(String)

    var errorDescription: String? {
        switch self {
        case .noKey:          return "No SSH key on this phone — add one in Tools › SSH key"
        case .connect(let m): return "Could not connect: \(m)"
        case .auth:           return "Authentication refused (is the key in the relay's authorized_keys?)"
        case .exec(let m):    return "Command failed: \(m)"
        }
    }
}

/// Connects to a relay over SSH and runs one command (Apple swift-nio-ssh).
/// Command execution only — no interactive shell.
actor SSHRunner {
    static let shared = SSHRunner()
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)

    func run(_ command: String, on server: Server, timeout: TimeInterval = 25) async throws -> SSHResult {
        let pem = Keychain.get("sshPrivateKey")
        guard !pem.isEmpty else { throw SSHError.noKey }
        let key = try OpenSSHKey.ed25519(fromPEM: pem)
        let user = server.sshUser.isEmpty ? "root" : server.sshUser

        let auth = PrivateKeyAuth(username: user, key: key)
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

        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: server.host, port: server.sshPort).get()
        } catch {
            throw SSHError.connect(error.localizedDescription)
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
            throw SSHError.exec(error.localizedDescription)
        }

        return await collector.result()
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

private final class PrivateKeyAuth: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let key: NIOSSHPrivateKey
    private var offered = false

    init(username: String, key: NIOSSHPrivateKey) {
        self.username = username
        self.key = key
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard availableMethods.contains(.publicKey), !offered else {
            nextChallengePromise.succeed(nil)
            return
        }
        offered = true
        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: .privateKey(.init(privateKey: key)))
        )
    }
}

// MARK: - Command channel

private actor OutputCollector {
    private var out = Data()
    private var err = Data()
    private var status: Int32?

    func appendOut(_ d: Data) { out.append(d) }
    func appendErr(_ d: Data) { err.append(d) }
    func setStatus(_ s: Int32) { status = s }
    func result() -> SSHResult {
        SSHResult(stdout: String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
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
        let isStderr = payload.type == .stdErr
        Task { [collector] in
            if isStderr { await collector.appendErr(bytes) } else { await collector.appendOut(bytes) }
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let status = event as? SSHChannelRequestEvent.ExitStatus {
            Task { [collector] in await collector.setStatus(Int32(status.exitStatus)) }
        }
        context.fireUserInboundEventTriggered(event)
    }
}
