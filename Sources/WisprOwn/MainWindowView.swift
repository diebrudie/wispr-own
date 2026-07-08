import SwiftUI

/// The hub window: sidebar (Home, Dictionary) + detail, Settings as a
/// sheet overlay — mirroring the Wispr Flow layout, violet-themed.
struct MainWindowView: View {
    @ObservedObject var app: AppState
    @State private var selection: Screen = .home
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum Screen: String, CaseIterable, Identifiable {
        case home, dictionary
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return "Home"
            case .dictionary: return "Dictionary"
            }
        }

        var icon: String {
            switch self {
            case .home: return "square.grid.2x2"
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
                        .tag(screen)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Spacer(minLength: 0)
                Divider()
                settingsButton
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection {
                case .home: HomeView(app: app)
                case .dictionary: DictionaryView(app: app)
                }
            }
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
