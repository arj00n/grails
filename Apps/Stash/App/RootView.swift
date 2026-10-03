import SwiftUI

struct RootView: View {
    @State private var selection: SidebarItem? = .all

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            PlaceholderGridView()
        }
    }
}
