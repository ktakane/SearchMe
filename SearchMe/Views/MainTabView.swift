import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }
            MapView()
                .tabItem {
                    Label("マップ", systemImage: "map.fill")
                }
            FamilyListView()
                .tabItem {
                    Label("家族", systemImage: "person.3.fill")
                }
            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
        }
        .accentColor(.orange)
    }
}
