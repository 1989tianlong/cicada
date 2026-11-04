import AppKit
import SwiftUI

/// SwiftUI that macOS 14 lacks, with what it gets instead.
extension View {
    /// The pointing hand over something clickable.
    @ViewBuilder func linkPointer() -> some View {
        if #available(macOS 15, *) {
            pointerStyle(.link)
        } else {
            onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
    }

    /// Where a scroll view's content sits against its bottom edge. macOS 14 doesn't report it:
    /// there the transcript keeps following new lines even after the reader scrolls up.
    @ViewBuilder func onScrollEdgeChange(_ action: @escaping (ScrollEdge, ScrollEdge) -> Void) -> some View {
        if #available(macOS 15, *) {
            onScrollGeometryChange(for: ScrollEdge.self) { g in
                ScrollEdge(distance: g.contentSize.height - g.contentOffset.y - g.containerSize.height,
                           height: g.contentSize.height, container: g.containerSize.height)
            } action: { old, new in action(old, new) }
        } else {
            self
        }
    }

    /// The content scrolled (macOS 15 and later).
    @ViewBuilder func onScrolled(_ action: @escaping () -> Void) -> some View {
        if #available(macOS 15, *) {
            onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, _ in action() }
        } else {
            self
        }
    }
}

/// How far the content's bottom is below the visible area, the content's height and the view's.
struct ScrollEdge: Equatable {
    var distance: CGFloat
    var height: CGFloat
    var container: CGFloat
}
