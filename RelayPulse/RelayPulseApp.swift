import BackgroundTasks
import SwiftUI
import UserNotifications

private enum RelayBackgroundRefresh {
    static let identifier = "com.baris.relaypulse.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// APNs cihaz token'i. Nobetci (VPS) bunu bilmeden push atamaz, o yuzden
/// Documents'a da yazilir: `devicectl device copy from` ile kablosuz cekilebilir,
/// kullanici ekrandan elle kopyalamak zorunda kalmaz.
enum APNSToken {
    static let key = "apnsDeviceToken"

    static var current: String? { UserDefaults.standard.string(forKey: key) }
    static var lastError: String? { UserDefaults.standard.string(forKey: key + "Error") }

    static func store(_ hex: String) {
        UserDefaults.standard.set(hex, forKey: key)
        UserDefaults.standard.removeObject(forKey: key + "Error")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("apns_token.txt")
        try? hex.write(to: url, atomically: true, encoding: .utf8)
    }

    static func store(error: String) {
        UserDefaults.standard.set(error, forKey: key + "Error")
    }
}

/// Registers the background refresh task the pre-SwiftUI way.
///
/// `.backgroundTask(.appRefresh:)` would be tidier but it is iOS 16+, and
/// `SceneBuilder` does not accept an `if #available` around a scene modifier, so
/// there is no way to apply it conditionally. Registering here works from iOS 13
/// on — one code path, and the iPhone 7 on iOS 15 still gets background refresh.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: RelayBackgroundRefresh.identifier,
            using: nil
        ) { task in
            let work = Task { @MainActor in
                await FleetStore.shared.refreshInBackground()
                RelayBackgroundRefresh.schedule()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        // Relay dustugunde yerel bildirim (ses + titresim). iPhone kilitliyken
        // ayni bildirim eslesmis Apple Watch'a otomatik yansir.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            // Uzak bildirim kaydi izin verilmeden yapilirsa token gelir ama
            // hicbir sey gosterilmez; izne bagla.
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        APNSToken.store(deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        APNSToken.store(error: error.localizedDescription)
    }

    /// Uygulama ondeyken de goster. Once sadece "relay-fix" gecerdi; alarmlar
    /// bastiriliyordu (kart zaten kirmiziya doner diye). Ama poll YALNIZCA
    /// uygulama ondeyken calisiyor — yani bastirilan tek durum, bildirimin
    /// uretilebildigi tek durumdu ve kullanici hicbir alarm gormuyordu.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound])
    }
}

@main
struct RelayPulseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Shared instance so the background task handler can reach the same store.
    @StateObject private var fleet = FleetStore.shared
    @StateObject private var ai = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(fleet)
                .environmentObject(ai)
                .tint(Color(.sRGB, red: 0.184, green: 0.49, blue: 0.965)) // matches Mac --accent
                .task {
                    SSHKeyStore.importSeedFileIfPresent()
                    ai.importSeedKeyIfPresent()
                }
                // Single-parameter form: the (old, new) closure is iOS 17+ and the
                // app supports iOS 15 so an iPhone 7 can run it.
                .onReceive(NotificationCenter.default.publisher(for: .relayFixRequested)) { _ in
                    Task { await fleet.runPendingFix() }
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        fleet.startPolling()
                        // Widget'tan gelen onarim istegi varsa hemen calistir.
                        Task { await fleet.runPendingFix() }
                    case .background:
                        fleet.stopPolling()
                        RelayBackgroundRefresh.schedule()
                    case .inactive:
                        break
                    @unknown default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var fleet: FleetStore
    @StateObject private var purchases = PurchaseStore()

    var body: some View {
        // No trial countdown and no wall. RelayPulse is free for the first few
        // relays and the purchase lifts that limit, so there is never a moment
        // where the app stops working and the operator is locked out of servers
        // they are still responsible for. Matches the desktop build.
        Group {
            if fleet.isConfigured {
                MainTabView()
            } else {
                ImportView()
            }
        }
        .environmentObject(purchases)
        .onAppear { fleet.isEntitled = purchases.isEntitled }
        .onChange(of: purchases.isEntitled) { fleet.isEntitled = $0 }
        .task { await purchases.start() }
    }
}
