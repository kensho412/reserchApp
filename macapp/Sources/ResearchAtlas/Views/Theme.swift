import SwiftUI

/// Dark, Cosense-ish palette. Slightly warm grays, bright tags, busy-but-light.
enum Theme {
    static let bg = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let cardBg = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let cardBgHover = Color(red: 0.16, green: 0.16, blue: 0.19)
    static let stroke = Color.white.opacity(0.08)
    static let textPrimary = Color(white: 0.93)
    static let textSecondary = Color(white: 0.60)
    static let textTertiary = Color(white: 0.42)
    static let accent = Color(red: 0.45, green: 0.78, blue: 0.95)      // links
    static let tagFg = Color(red: 0.55, green: 0.85, blue: 0.70)       // #tags
    static let tagBg = Color(red: 0.18, green: 0.30, blue: 0.26)
    static let tagActiveBg = Color(red: 0.30, green: 0.55, blue: 0.45)
}

/// Cosense-style #tag chip.
struct TagChip: View {
    let name: String
    var active: Bool = false
    var count: Int? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        let label = HStack(spacing: 3) {
            Text("#\(name)").font(.system(size: 12, weight: .medium))
            if let count, count > 0 {
                Text("\(count)").font(.system(size: 10)).foregroundColor(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(active ? Theme.tagActiveBg : Theme.tagBg)
        .foregroundColor(active ? .white : Theme.tagFg)
        .clipShape(Capsule())

        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

/// Wrapping horizontal layout (macOS 13 Layout protocol).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
