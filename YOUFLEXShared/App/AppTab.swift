import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case live
    case movies
    case series
    case search
    case downloads
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .live: "Live"
        case .movies: "Movies"
        case .series: "Series"
        case .search: "Search"
        case .downloads: "Downloads"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .live: "dot.radiowaves.left.and.right"
        case .movies: "film"
        case .series: "square.stack.3d.up"
        case .search: "magnifyingglass"
        case .downloads: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }

    static var primaryPhoneTabs: [AppTab] {
        [.home, .live, .movies, .series, .search]
    }

    static var secondaryPhoneTabs: [AppTab] {
        [.downloads, .settings]
    }
}
