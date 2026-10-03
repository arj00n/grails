import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case inbox = "Inbox"
    case all = "All"
    case liked = "Liked"
    case untagged = "Untagged"
    case trash = "Trash"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .all: "square.grid.2x2"
        case .liked: "heart"
        case .untagged: "tag.slash"
        case .trash: "trash"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.symbol)
                .tag(item)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
    }
}
