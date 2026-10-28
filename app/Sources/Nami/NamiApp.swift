import AVFoundation
import SwiftUI

@main
struct NamiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.fr.rawValue
    @AppStorage("titleLanguage") private var titleLanguage = TitleLanguage.romaji.rawValue

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Language strings are read when views are built, so rebuild on change.
                .id("\(appLanguage)-\(titleLanguage)")
                .environment(\.locale, Locale(identifier: appLanguage))
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.36, green: 0.62, blue: 1.0))
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in Engine.shared.start() }
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }
}

@MainActor
enum Orientation {
    static func set(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientations = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

struct RootView: View {
    @StateObject private var anilist = AniList.shared
    @StateObject private var extensions = ExtensionStore.shared

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label(t("Accueil", "Home"), systemImage: "house.fill") }
            SearchView()
                .tabItem { Label(t("Recherche", "Search"), systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label(t("Réglages", "Settings"), systemImage: "gearshape.fill") }
        }
        .environmentObject(anilist)
        .environmentObject(extensions)
        .task {
            await anilist.loadViewer()
            await extensions.refresh()
        }
    }
}
