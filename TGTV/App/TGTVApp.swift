import SwiftUI

@main
struct TGTVApp: App {
    @StateObject private var td = TDLibService.shared
    @StateObject private var store = Store.shared
    @StateObject private var backup = CloudBackup.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if td.isReady && store.chatsConfigured {
                    MainTabs()
                } else if td.isReady {
                    NavigationStack { ChatSelectionView() }
                        .environmentObject(td)
                        .environmentObject(store)
                } else {
                    LoginView()
                }
            }
            .environmentObject(td)
            .environmentObject(store)
            .environmentObject(backup)
            .preferredColorScheme(.dark)
            .onAppear { td.start() }
            .task {
                guard td.isReady else { return }
                await backup.restore()
            }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { FavouritesView() }
                .tabItem { Label("Favourites", systemImage: "heart.fill") }
            NavigationStack { RequestsView() }
                .tabItem { Label("Requests", systemImage: "clapperboard") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.red)
        .overlay(alignment: .top) {
            if td.busy {
                ProgressView()
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }
}
