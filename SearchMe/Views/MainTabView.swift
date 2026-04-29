import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var subManager: SubscriptionManager
    @State private var selectedTab = 0
    @State private var showSafetyReminderSheet = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(0)
            MapView()
                .tabItem { Label("マップ", systemImage: "map.fill") }
                .tag(1)
            Group {
                if subManager.isSubscribed {
                    DashboardView()
                } else {
                    FamilyListView()
                }
            }
            .tabItem { Label(subManager.planType.groupLabel, systemImage: "person.3.fill") }
            .tag(2)
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .accentColor(.orange)
        .onChange(of: appState.showSafetyReminder) { newValue in
            if newValue { showSafetyReminderSheet = true }
        }
        .onChange(of: subManager.planType) { newPlan in
            guard appState.isSetupComplete else { return }
            Task {
                try? await APIService.shared.updateGroupPlan(
                    groupId: appState.groupId,
                    maxMembers: newPlan.maxMembers
                )
            }
        }
        .fullScreenCover(isPresented: $showSafetyReminderSheet) {
            SafetySheet(
                isPresented: $showSafetyReminderSheet,
                isStopping: false,
                isReminder: true,
                onCompleted: {
                    selectedTab = 0
                    appState.showSafetyReminder = false
                }
            )
            .environmentObject(appState)
        }
    }
}
