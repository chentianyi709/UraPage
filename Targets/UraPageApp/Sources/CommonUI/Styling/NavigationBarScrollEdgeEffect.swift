import SwiftUI

extension View {
    /// Keeps the soft transition between scrolling content and navigation bars across iOS versions.
    func appNavigationBarScrollEdgeEffect() -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
    }
}
