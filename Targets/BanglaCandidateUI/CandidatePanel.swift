import AppKit
import SwiftUI
import BanglaEngine

/// Floating panel that hosts the SwiftUI candidate list.
/// `becomesKeyOnlyIfNeeded = true` so the host app keeps key status.
public final class CandidatePanel: NSPanel {
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.animationBehavior = .none
    }

    public func show(at screenPoint: NSPoint, candidates: [Candidate], selectedIndex: Int = 0) {
        let host = CandidateHostingView(candidates: candidates, selectedIndex: selectedIndex)
        self.contentView = host
        self.setFrameOrigin(screenPoint)
        self.orderFrontRegardless()
    }

    public func hide() {
        self.orderOut(nil)
        self.contentView = nil
    }
}

/// NSHostingView wrapper for the SwiftUI candidate list.
public final class CandidateHostingView: NSHostingView<CandidateView> {
    public init(candidates: [Candidate], selectedIndex: Int) {
        super.init(rootView: CandidateView(candidates: candidates, selectedIndex: selectedIndex))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
    required init(rootView: CandidateView) { super.init(rootView: rootView) }
}