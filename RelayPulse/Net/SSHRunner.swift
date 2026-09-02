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
        case .noKey:          return "Telefon SSH anahtarı yok — Ayarlar › SSH'ten ekle"
        case .connect(let m): return "Bağlanamadı: \(m)"
        case .auth:           return "Kimlik doğrulama reddedildi (anahtar relay'de authorized_keys'te mi?)"
        case .exec(let m):    return "Komut çalışmadı: \(m)"
        }
    }
}

/// Relay'e SSH ile bağlanıp tek bir komut çalıştırır (Apple swift-nio-ssh).
/// Sadece komut çalıştırma — interaktif kabuk yok.
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
        defer { try? channel.close().wait() }

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
            // Kanal kapanana kadar bekle (komut bitti demektir), en fazla `timeout`.
            try await withThrowingTaskGroup(of: Void.self) { g in
                g.addTask { try await child.closeFuture.get() }
                g.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw SSHError.exec("zaman aşımı (\(Int(timeout))s)")
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

// MARK: - Kimlik doğrulama

private final class AcceptAllHostKeys: NIOSSHClientServerAuthenticationDelegate {
    // Relay host anahtarları sabit değil (yeniden kurulum/multi-IP). Kimlik
    // dogrulamasi ozel anahtarla yapiliyor; Mac tarafi da StrictHostKeyChecking=accept-new.
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

// MARK: - Komut kanalı

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
