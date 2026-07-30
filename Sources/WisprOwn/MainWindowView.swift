import SwiftUI

/// The hub window: sidebar (Home, Insights, Dictionary) + detail, Settings as a
/// sheet overlay — mirroring the Wispr Flow layout, violet-themed.
struct MainWindowView: View {
    @ObservedObject var app: AppState
    @State private var selection: Screen = .home
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum Screen: String, CaseIterable, Identifiable {
        case home, insights, dictionary
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return "Home"
            case .insights: return "Insights"
            case .dictionary: return "Dictionary"
            }
        }

        var icon: String {
            switch self {
            case .home: return "square.grid.2x2"
            case .insights: return "chart.bar"
            case .dictionary: return "character.book.closed"
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading, spacing: 0) {
                wordmark
                List(Screen.allCases, selection: $selection) { screen in
                    Label(screen.title, systemImage: screen.icon)
                        .font(.system(size: 15))
                        .padding(.vertical, 3)
                        .tag(screen)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Spacer(minLength: 0)
                Divider()
                settingsButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The sidebar reads as page, not panel: its own vibrancy material is
            // replaced by the flat window colour, edge to edge.
            .background(Theme.windowBackground)
            .toolbarBackground(Theme.windowBackground, for: .windowToolbar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 260)
        } detail: {
            Group {
                switch selection {
                case .home: HomeView(app: app)
                case .insights: InsightsView(app: app)
                case .dictionary: DictionaryView(app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Painted, not clipped. `.clipShape` here forces every child into a
            // clipped container and a `List` can't resolve a size against it —
            // that blanked the whole split view, sidebar included.
            .background(Theme.contentBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
            .padding(EdgeInsets(top: 8, leading: 0, bottom: 10, trailing: 10))
            .background(Theme.windowBackground)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation {
                            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help("Hide or show the sidebar")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accent)
        .sheet(isPresented: $showSettings) {
            SettingsOverlayView(app: app)
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(
                    LinearGradient(colors: [Theme.accentFixed, Theme.accentDeep],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            Text("WisprOwn")
                .font(.headline)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .keyboardShortcut(",", modifiers: .command)
    }
}
