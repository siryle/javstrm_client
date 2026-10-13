import SwiftUI

@main
struct JavStrmApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Palette.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hideInBackground") private var hideInBackground = true

    var body: some View {
        @Bindable var session = session
        ZStack {
            switch session.phase {
            case .setup, .login: ConnectionView()
            case .connected: MainTabView().id(session.connectionID)
            }
            if hideInBackground && scenePhase != .active {
                PrivacyCurtain()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .background(PrivacyShield(enabled: hideInBackground, isVisible: scenePhase != .active))
        .task { await session.bootstrap() }
        .onChange(of: scenePhase) { _, phase in session.setForeground(phase == .active) }
        .alert("JavStrm", isPresented: Binding(
            get: { session.notice != nil },
            set: { if !$0 { session.notice = nil } }
        ), presenting: session.notice) { _ in
            Button("好", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
    }
}

private struct MainTabView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        TabView {
            NavigationStack { LibraryView() }
                .tabItem { Label("媒体库", systemImage: "square.grid.2x2") }
            NavigationStack { DiscoverView() }
                .tabItem { Label("发现", systemImage: "safari") }
            NavigationStack { SubscriptionsView() }
                .tabItem { Label("订阅", systemImage: "bookmark") }
            NavigationStack { TasksView() }
                .tabItem { Label("任务", systemImage: "arrow.triangle.2.circlepath") }
                .badge(session.activeCount)
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
    }
}

struct PrivacyCurtain: View {
    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.shield").font(.system(size: 44, weight: .light))
                Text("JavStrm").font(.system(.title, design: .serif).weight(.semibold))
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("内容已隐藏")
        }
    }
}
