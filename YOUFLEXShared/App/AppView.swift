import SwiftUI

struct AppView: View {
    @Bindable var model: AppModel
    @State private var sidebarSelection: AppTab? = .home
    @State private var secondarySheet: AppTab?

    var body: some View {
        Group {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                sidebarLayout
            } else {
                phoneLayout
            }
            #else
            sidebarLayout
            #endif
        }
        .preferredColorScheme(.dark)
    }

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: $sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationTitle("YOUFLEX")
        } detail: {
            NavigationStack {
                detailView(for: sidebarSelection ?? .home)
            }
        }
        .tint(AppTheme.Colors.accent)
    }

    private var phoneLayout: some View {
        TabView(selection: $sidebarSelection) {
            ForEach(AppTab.primaryPhoneTabs) { tab in
                NavigationStack {
                    detailView(for: tab)
                        .toolbar {
                            ToolbarItem {
                                Menu("More") {
                                    ForEach(AppTab.secondaryPhoneTabs) { secondary in
                                        Button(secondary.title) {
                                            secondarySheet = secondary
                                        }
                                    }
                                }
                            }
                        }
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(Optional(tab))
            }
        }
        .sheet(item: $secondarySheet) { tab in
            NavigationStack {
                detailView(for: tab)
            }
        }
        .tint(AppTheme.Colors.accent)
    }

    @ViewBuilder
    private func detailView(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(model: model)
        case .live:
            LiveView(model: model)
        case .movies:
            MoviesView(model: model)
        case .series:
            SeriesView(model: model)
        case .search:
            SearchView(model: model)
        case .downloads:
            DownloadsView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }
}
