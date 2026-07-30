import SwiftUI

/// The hub window: sidebar (Home, Insights, Dictionary) + detail, Settings as a
/// sheet overlay — mirroring the Wispr Flow layout, violet-themed.
struct MainWindowView: View {
    @ObservedObject var app: AppState
    @State private var selection: Screen = .home
    @State private var showSettings = false
    @State private var sidebarVisible = true

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
        // A plain HStack, not NavigationSplitView. The split view draws its own
        // sidebar panel — inset, rounded, with vibrancy — and there is no
        // supported way to turn that off; every attempt to cover it left an
        // edge. Laying the two columns out directly is less code and the
        // sidebar genuinely becomes part of the page.
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar
                    .frame(width: 216)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Group {
                switch selection {
                case .home: HomeView(app: app)
                case .insights: InsightsView(app: app)
                case .dictionary: DictionaryView(app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.contentBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
            .padding(EdgeInsets(top: 8, leading: 0, bottom: 10, trailing: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Hide or show the sidebar")
            }
        }
        .toolbarBackground(Theme.windowBackground, for: .windowToolbar)
        .tint(Theme.accent)
        .sheet(isPresented: $showSettings) {
            SettingsOverlayView(app: app)
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark
            VStack(spacing: 2) {
                ForEach(Screen.allCases) { screen in
                    sidebarItem(screen)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            Spacer(minLength: 0)
            Divider().padding(.horizontal, 10)
            settingsButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarItem(_ screen: Screen) -> some View {
        Button {
            selection = screen
        } label: {
            Label(screen.title, systemImage: screen.icon)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    selection == screen ? AnyShapeStyle(Theme.tintedFill) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(selection == screen ? Theme.accent : .primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
