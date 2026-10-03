import SwiftUI

/// Temporary grid until the NSCollectionView grid lands in M2.
struct PlaceholderGridView: View {
    var body: some View {
        ContentUnavailableView(
            "Nothing here yet",
            systemImage: "photo.on.rectangle.angled",
            description: Text("Drop images here to start your library.")
        )
    }
}
