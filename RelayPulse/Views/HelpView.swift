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
                stepRow(1, "Add a server", "Tap + on the Servers screen (or Add server on the first screen). Give it a name and its IP address.")
                stepRow(2, "Choose how the app logs in", "Under SSH, type the server's password — for a VPS, the root password your provider sent you. Or use an SSH key (safer, see below). You can set both; the key is tried first.")
                stepRow(3, "Save", "Within a few seconds the server turns green, yellow or red. Tap it for details and tools.")
                stepRow(4, "Optional: the agent", "Only if you already installed the RelayPulse agent from the Mac app: enter its port and token, or import the fleet from the Mac. Without it everything still works over SSH.")
            } header: {
                Text("First steps")
            }

            Section {
                Text("The app signs in with an SSH key or with the server's own password — the same two choices as on the Mac. Password: open the server (Add server or Edit) and fill in Password under SSH. Key (safer): make one that belongs to this phone alone, so losing the phone costs you one key and nothing else.")
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
                Text("Logging in: password or SSH key")
            }

            Section {
                helpRow("Name", "Any label you like. It is what the cards and alerts show.")
                helpRow("Host / IP", "The server's IP address or hostname.")
                helpRow("Agent port", "0 means no agent: the server is read over SSH and nothing is installed on it. If you installed the RelayPulse agent from the Mac app, its port — usually 19191.")
                helpRow("Scheme", "HTTPS for the agent. HTTP only for an agent you set up without encryption.")
                helpRow("Agent token", "The agent's own password. Importing from the Mac fills it in; if it changes, RelayPulse reads the new one over SSH by itself.")
                helpRow("SSH user and port", "Usually root and 22. Change them only if your server uses something else.")
                helpRow("Password", "The server's login password. Leave it empty if this phone's SSH key is on the server. Kept in the iOS Keychain.")
            } header: {
                Text("Server fields")
            }

            Section {
                helpRow("Servers", "Tap a server to edit it, swipe left to delete it. Import JSON loads a list exported from RelayPulse on the Mac (Settings › Monitoring › Export for iPhone), agent tokens included.")
                helpRow("Try demo fleet", "Sample servers to look around with. Nothing is contacted. Turn it off to get back to your own list.")
                helpRow("Poll interval", "How often each server is read. Shorter is fresher; longer is lighter on your servers and on the battery.")
                helpRow("Offline after … failures", "How many failed readings in a row turn a server red. One fewer shows yellow. A single miss stays green — short network hiccups are common and are not outages.")
                helpRow("Notifications", "Allow them and send a test. Alerts arrive while the app is open and during the background refreshes iOS allows. The push token is only for people who run their own always-on watcher.")
                helpRow("Agent security", "The app remembers each agent's certificate and refuses a different one. Reset only after reinstalling an agent.")
                helpRow("License", "Shows whether you are on the free tier, the preview or the purchase. Restore Purchases brings back a purchase made on this Apple Account, on iPhone or Mac.")
                helpRow("What counts as \"up\"", "Which service to check on each server, e.g. nginx or docker — separate several with spaces. Ports: if none of those services exists, a server listening on one of these ports still counts as up. Leave both empty for the defaults.")
                helpRow("Remove all servers", "Deletes the server list and saved passwords from this phone. Nothing changes on the servers.")
            } header: {
                Text("Settings")
            }

            Section {
                helpRow("htop", "Load, the busiest processes and disk use — a snapshot at the moment you tap Run.")
                helpRow("Service log", "The last lines of the watched service's log (journalctl).")
                helpRow("HTTPS agent check", "Whether the agent answers on its port.")
                helpRow("Nyx and Config", "Only for Anyone/Tor relays; hidden on other servers.")
                helpRow("AI API key and commands", "Optional. With your own OpenAI or Anthropic key the app explains an error and suggests one of your fix commands. Nothing runs until you tap it.")
                helpRow("SSH key", "Create, paste or import this phone's key, and install it on a server with its password.")
                helpRow("Activity log", "What the app diagnosed and which commands ran.")
                helpRow("Per server", "Every tool for one server, plus the fix commands.")
            } header: {
                Text("Tools")
            }

            Section {
                helpRow("Password refused",
                        "Wrong password, or the server has password login switched off, or allows it only through keyboard-interactive. Use an SSH key instead.")
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
                Text("The agent is optional. SSH alone reads CPU, memory, disk and traffic; the agent answers faster and is lighter on large fleets, because no SSH session is opened for every reading.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted(scheme))
                Text("Install it from the Mac app; it makes the token itself. On the phone, import the fleet from the Mac, or enter the port and token in the server's settings.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted(scheme))
            } header: {
                Text("Metrics agent")
            }

            Section {
                stateRow("Online", Theme.ok(scheme), "Reachable, and the watched service is running.")
                stateRow("Warning", Theme.warn(scheme), "Reachable, but something is wrong — usually the watched service is not active.")
                stateRow("Stale", Theme.warn(scheme), "Readings were missed, but fewer than the Offline limit. Usually a passing network hiccup, not an outage.")
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

    private func stepRow(_ n: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.accent(scheme)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(Theme.muted(scheme))
            }
        }
        .padding(.vertical, 2)
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
