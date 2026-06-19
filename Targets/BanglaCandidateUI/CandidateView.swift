import SwiftUI
import BanglaEngine

/// SwiftUI candidate list. Keyboard navigation (Up/Down/Enter/1-9)
/// is handled by the IME controller; this view reflects the current
/// selection visually.
public struct CandidateView: View {
    public let candidates: [Candidate]
    public let selectedIndex: Int

    public init(candidates: [Candidate], selectedIndex: Int) {
        self.candidates = candidates
        self.selectedIndex = selectedIndex
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(candidates.prefix(9).enumerated()), id: \.element.id) { idx, c in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .center)
                    Text(c.bangla)
                        .font(.system(size: 16))
                        .foregroundStyle(idx == selectedIndex ? .white : .primary)
                    Spacer()
                    if !c.latinHint.isEmpty {
                        Text(c.latinHint)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(idx == selectedIndex ? Color.accentColor.opacity(0.85) : Color(nsColor: .windowBackgroundColor))
                )
                .contentShape(Rectangle())
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)
        )
        .frame(minWidth: 240, idealWidth: 280, minHeight: 40)
    }
}