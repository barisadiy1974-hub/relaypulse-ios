import SwiftUI

/// In-app help. The app used to state what an SSH key must look like but never
/// how to produce one, so a new operator had nowhere to go but the terminal and
/// a guess. Everything here is the short version; the website carries the long one.
struct HelpView: View {
    @Environment(\.colorScheme) private var scheme

    private static let setupURL = URL(string: "https://barisadiy1974-hub.github.io/relaypulse/setup.html")!
    private static let guideURL = URL(string: "https://github.com/barisadiy1974-hub/relaypulse/blob/main/GUIDE.md")!

    var body: some View {
        Form {
            Section {
                Text("RelayPulse reads your servers over SSH, or over the metrics agent if you installed one. Nothing runs on a server of ours and no account is created.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted(scheme))
            }

            Section {
                Text("The app signs in with a key, not a password — there is no password field on iPhone, by design. Make a key that belongs to this phone alone, so losing the phone costs you one key and nothing else.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted(scheme))

                Text("Easiest: Tools › SSH key › Create a key on this phone. Then either Install on a server with its password — used once, never stored — or copy the public key into the server's ~/.ssh/authorized_keys yourself.")
                    .font(.footnote)

                Text("Or make it on a computer instead:")
                    .font(.footnote.weight(.semibold))

                Text("1. On your Mac or PC, create the key:")
                    .font(.footnote)
                CodeRow(#"ssh-keygen -t ed25519 -f ~/.ssh/relaypulse_phone -C "relaypulse-phone" -N """#)

                Text("2. Put the public half on each server:")
                    .font(.footnote)
                CodeRow("ssh-copy-id -i ~/.ssh/relaypulse_phone.pub root@YOUR.SERVER.IP")

                Text("3. Copy the private half to your clipboard, then paste it under SSH key:")
                    .font(.footnote)
                CodeRow("pbcopy < ~/.ssh/relaypulse_phone")

                Text("You can also AirDrop the key file to the phone and use Import from file. The key must be ed25519 with no passphrase — that is what the -N \"\" above does.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted(scheme))

                Link(destination: Self.setupURL) {
                    Label("Full setup guide, with troubleshooting", systemImage: "safari")
                }
            } header: {
                Text("Setting up an SSH key")
            }

            Section {
                helpRow("Authentication refused",
                        "The key is not in that server's authorized_keys, or it landed under a different user. Root connects as root: the key belongs in /root/.ssh/authorized_keys.")
                helpRow("The app rejects the key",
                        "It is not an unencrypted ed25519 OpenSSH key. An RSA key, a PuTTY .ppk, a key with a passphrase, or the .pub file by mistake are all refused.")
                helpRow("Connection times out",
                        "Usually the wrong SSH port, or a firewall that does not allow the network your phone is on.")
                helpRow("It worked, then stopped",
                        "Some servers run fail2ban. Repeated failures ban the source address for a while, including yours.")
            } header: {
                Text("When SSH will not connect")
            }

            Section {
                Text("The agent is optional. It reports more than SSH alone can — CPU, memory, disk and traffic — without opening a shell for every reading.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted(scheme))
                Text("Install it from the desktop app; it generates the token itself and stores it encrypted. You never type a token by hand. On this phone you only need it if you already installed the agent on that server.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted(scheme))
            } header: {
                Text("Metrics agent")
            }

            Section {
                stateRow("Online", Theme.ok(scheme), "Reachable, and the watched service is running.")
                stateRow("Warning", Theme.warn(scheme), "Reachable, but something is wrong — usually the watched service is not active.")
                stateRow("Stale", Theme.warn(scheme), "One reading was missed. Almost always a passing network hiccup, not an outage.")
                stateRow("Offline", Theme.err(scheme), "Several readings in a row failed. This one is real.")
                Text("A server with zero connections is not an error. It is running and simply has no traffic yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted(scheme))
            } header: {
                Text("What the colours mean")
            }

            Section {
                Text("RelayPulse watches up to \(FleetStore.freeRelayLimit) servers free, with nothing held back and nothing that expires. One purchase lifts the limit for the whole fleet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted(scheme))
                Text("The purchase covers iPhone and Mac together. If you bought it on one, use Restore Purchases on the other with the same Apple Account.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted(scheme))
            } header: {
                Text("Free tier and purchase")
            }

            Section {
                Link(destination: Self.guideURL) {
                    Label("User guide", systemImage: "book")
                }
                Link(destination: URL(string: "mailto:baris.adiy1974@gmail.com")!) {
                    Label("Email support", systemImage: "envelope")
                }
            } header: {
                Text("More")
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.caption).foregroundStyle(Theme.muted(scheme))
        }
        .padding(.vertical, 2)
    }

    private func stateRow(_ name: String, _ colour: Color, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(colour).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(Theme.muted(scheme))
            }
        }
        .padding(.vertical, 2)
    }
}

/// A command the operator has to run on a real computer. Typing these on a phone
/// keyboard is how quotes and dashes get mangled, so the only interaction offered
/// is copying it verbatim.
private struct CodeRow: View {
    let command: String
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false

    init(_ command: String) { self.command = command }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(command)
                .font(.caption2.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIPasteboard.general.string = command
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Theme.ok(scheme) : Theme.accent(scheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "Copied" : "Copy command")
        }
        .padding(.vertical, 2)
    }
}
