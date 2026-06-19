import Cocoa
import InputMethodKit
import BanglaEngine
import BanglaStorage
import BanglaCandidateUI

/// The IMK input controller. One instance per active input session.
///
/// Hot path (marked-text updates) runs fully synchronous via `PhoneticResolver`
/// from the bundled layout rules — no actor hops, so typing never blocks on the
/// main thread. Candidate ranking is fired off as a detached task against the
/// shared `IMEEngine` actor and the result is applied to the candidate panel when
/// it arrives.
@objc(BanglaInputController)
final class BanglaInputController: IMKInputController {

    private let bootstrap = IMEBootstrap.shared
    private var session: CompositionSession
    private let panel = CandidatePanel()
    private var candidates: [Candidate] = []
    private var selectedCandidateIndex = 0

    override init() {
        let layoutId = IMEBootstrap.shared.activeLayoutId
        self.session = CompositionSession(layoutId: layoutId)
        super.init()
    }

    override func activateServer(_ sender: Any!) {
        let layoutId = bootstrap.activeLayoutId
        session = CompositionSession(layoutId: layoutId)
        try? bootstrap.sessionRepo?.setLayout(layoutId)
    }

    override func deactivateServer(_ sender: Any!) {
        cancelComposition(client: sender as? IMKTextInput)
        panel.hide()
    }

    // MARK: - Key dispatch

    /// Handle function/arrow/escape/backspace/return + candidate nav keys.
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        let client = sender as? IMKTextInput

        if event.type != .keyDown { return false }

        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        // Candidate navigation when the panel is showing.
        if !candidates.isEmpty {
            switch keyCode {
            case 126: // up
                selectedCandidateIndex = (selectedCandidateIndex - 1 + candidates.count) % candidates.count
                showPanel(client: client); return true
            case 125: // down
                selectedCandidateIndex = (selectedCandidateIndex + 1) % candidates.count
                showPanel(client: client); return true
            case 36, 76: // return / enter
                commitSelectedCandidate(client: client); return true
            case 53: // escape
                cancelComposition(client: client); return true
            default:
                break
            }
            // Digit 1-9 selects candidate N (no modifiers).
            if modifiers.isEmpty, let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
               (0x0031...0x0039).contains(scalar.value) {
                let idx = Int(scalar.value) - 0x0031
                if idx < candidates.count { selectedCandidateIndex = idx; commitSelectedCandidate(client: client); return true }
            }
        }

        switch keyCode {
        case 51:  // backspace
            return doBackspace(client: client)
        case 53:  // escape
            cancelComposition(client: client); return true
        case 36, 76:  // return / enter
            return commitComposed(client: client)
        case 49:  // space
            return commitComposed(client: client, thenInsert: " ")
        default:
            break
        }

        return false
    }

    /// Handle printable text input.
    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        guard let string = string, !string.isEmpty else { return false }
        let client = sender as? IMKTextInput
        let layoutId = session.lastLayoutId
        guard let layout = bootstrap.layout(for: layoutId) else { return false }

        // Fixed layouts: map each char to a glyph and insert directly.
        if layout.kind == .fixed {
            return processFixed(string: string, layout: layout, client: client)
        }

        // Phonetic: only ASCII letters and a few punctuation feed the buffer.
        let allowed = string.unicodeScalars.allSatisfy {
            ($0.isASCII && ($0.value >= 0x41 && $0.value <= 0x5A || $0.value >= 0x61 && $0.value <= 0x7A))
            || $0 == "`" || $0 == "." || $0 == "-" || $0 == "~"
        }
        guard allowed else { return false }

        return feedPhonetic(string, client: client)
    }

    // MARK: - Fixed layouts

    private func processFixed(string: String, layout: Layout, client: IMKTextInput?) -> Bool {
        var out = ""
        for ch in string {
            if let glyph = layout.keymap[String(ch)] { out += glyph }
            else { out += String(ch) }
        }
        guard !out.isEmpty else { return false }
        client?.insertText(out, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        return true
    }

    // MARK: - Phonetic composition

    private func feedPhonetic(_ string: String, client: IMKTextInput?) -> Bool {
        var buf = session.buffer
        // Append to the current segment's latin, then re-resolve the whole buffer.
        let newLatin = buf.latin + string
        guard let resolver = bootstrap.resolver(for: session.lastLayoutId) else { return false }
        let resolution = resolver.resolve(newLatin)
        buf = CompositionBuffer()
        buf.append(latin: newLatin, bangla: resolution.bangla, alternates: resolution.alternates)
        session.state.buffer = buf
        session.state.phase = .composing
        updateMarkedText(client: client)
        requestCandidates(latin: newLatin, banglaPrefix: resolution.bangla, client: client)
        return true
    }

    private func doBackspace(client: IMKTextInput?) -> Bool {
        guard session.hasComposition else { return false }
        var buf = session.buffer
        let _ = buf.backspace()
        let newLatin = buf.latin
        if newLatin.isEmpty {
            session.reset()
            client?.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                  replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            panel.hide()
            candidates = []
            return true
        }
        guard let resolver = bootstrap.resolver(for: session.lastLayoutId) else { return true }
        let resolution = resolver.resolve(newLatin)
        var fresh = CompositionBuffer()
        fresh.append(latin: newLatin, bangla: resolution.bangla, alternates: resolution.alternates)
        session.state.buffer = fresh
        updateMarkedText(client: client)
        requestCandidates(latin: newLatin, banglaPrefix: resolution.bangla, client: client)
        return true
    }

    private func commitComposed(client: IMKTextInput?, thenInsert extra: String? = nil) -> Bool {
        guard session.hasComposition else { return false }
        let text = session.buffer.bangla
        client?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        if let extra = extra {
            client?.insertText(extra, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
        recordCommit(chosen: text, source: "composed")
        session.reset()
        panel.hide()
        candidates = []
        return true
    }

    private func commitSelectedCandidate(client: IMKTextInput?) {
        guard candidates.indices.contains(selectedCandidateIndex) else { return }
        let chosen = candidates[selectedCandidateIndex]
        client?.insertText(chosen.bangla, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        recordCommit(chosen: chosen.bangla, source: chosen.source.rawValue)
        session.reset()
        panel.hide()
        candidates = []
    }

    private func cancelComposition(client: IMKTextInput?) {
        session.reset()
        candidates = []
        client?.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        panel.hide()
    }

    // MARK: - Marked text + candidates

    private func updateMarkedText(client: IMKTextInput?) {
        let bangla = session.buffer.bangla
        let len = bangla.count
        client?.setMarkedText(bangla,
                              selectionRange: NSRange(location: len, length: 0),
                              replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func requestCandidates(latin: String, banglaPrefix: String, client: IMKTextInput?) {
        let layoutId = session.lastLayoutId
        let context: [String] = []  // prior committed tokens; wired up in a later pass
        Task { [bootstrap, weak self] in
            let list = await bootstrap.engine.rank(latin: latin,
                                                    banglaPrefix: banglaPrefix,
                                                    layoutId: layoutId,
                                                    context: context)
            await MainActor.run { self?.applyCandidates(list, client: client) }
        }
    }

    @MainActor
    private func applyCandidates(_ list: CandidateList, client: IMKTextInput?) {
        candidates = list.entries
        selectedCandidateIndex = 0
        if candidates.isEmpty { panel.hide(); return }
        showPanel(client: client)
    }

    private func showPanel(client: IMKTextInput?) {
        let point = caretScreenPoint(client: client)
        panel.show(at: point, candidates: candidates, selectedIndex: selectedCandidateIndex)
    }

    /// Best-effort caret position. Uses NSTextInputClient.firstRect; falls back
    /// to the mouse location, then to the lower-left of the main screen.
    private func caretScreenPoint(client: IMKTextInput?) -> NSPoint {
        if let client = client {
            let sel = client.selectedRange()
            var rect = client.firstRect(forCharacterRange: NSRange(location: sel.location, length: 0),
                                        actualRange: nil)
            // firstRect returns screen coords with origin top-left; NSPanel uses
            // bottom-left. Flip and offset just below the caret.
            if let screen = NSScreen.main {
                rect.origin.y = screen.frame.maxY - rect.origin.y + rect.height
            }
            return rect.origin
        }
        let mouse = NSEvent.mouseLocation
        if mouse.x > 0 || mouse.y > 0 { return NSPoint(x: mouse.x, y: mouse.y - 4) }
        return NSPoint(x: 40, y: 80)
    }

    // MARK: - Learning

    private func recordCommit(chosen: String, source: String) {
        let latin = session.buffer.latin
        Task { [bootstrap, weak self] in
            guard self != nil else { return }
            await bootstrap.engine.observeCommit(
                latin: latin,
                chosen: Candidate(bangla: chosen, latinHint: latin, source: .lexicon),
                context: [],
                sessionId: UUID(),
                appBundleHash: Bundle.main.bundleIdentifier
            )
        }
    }

    override func commitComposition(_ sender: Any!) {
        commitComposed(client: sender as? IMKTextInput)
    }
}