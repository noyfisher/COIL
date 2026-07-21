import SwiftUI

/// A Button that invokes the environment `dismiss` action, with the
/// `@Environment(\.dismiss)` read isolated inside this leaf view.
///
/// Do NOT read `@Environment(\.dismiss)` directly in a view that also registers a
/// `navigationDestination`. On iOS 18, pushing the destination changes the dismiss
/// action's identity, which invalidates the reading view, which re-registers the
/// destination, which changes dismiss again — an AttributeGraph cycle that pins the
/// main thread at 100% and freezes the app (P1 "Generate Plan" freeze, 2026-06-09).
/// Scoping the read here means only this leaf re-renders when the dismiss action
/// changes, which breaks the cycle.
struct DismissButton<Label: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: { dismiss() }) {
            label()
        }
    }
}
