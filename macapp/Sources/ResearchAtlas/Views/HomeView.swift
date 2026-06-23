import SwiftUI

/// Cosense-style home: search bar on top, tag cloud, then a card grid of pages.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchBar
                if let msg = state.statusMessage { statusBanner(msg) }
                if !state.activeTags.isEmpty { activeFilterRow }
                tagCloud
                Divider().overlay(Theme.stroke)
                recentHeader
                cardGrid
            }
            .padding(20)
        }
        .background(Theme.bg)
        .task { await state.reload() }
    }

    // MARK: search
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Theme.textSecondary)
            TextField("検索…  例: chladni #installation #instrument",
                      text: $state.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(Theme.textPrimary)
                .focused($searchFocused)
                .onSubmit { Task { await state.search() } }
                .onChange(of: state.searchText) { _ in
                    // Live filter as the user types (debounce-free for a small DB).
                    Task { await state.search() }
                }
            if !state.searchText.isEmpty {
                Button { state.searchText = ""; Task { await state.search() } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textTertiary)
                }.buttonStyle(.plain)
            }
            Button { Task { await state.createNewPage() } } label: {
                Label("新規ページ", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.22))
                    .foregroundColor(Theme.accent)
                    .clipShape(Capsule())
            }.buttonStyle(.plain)
            .help("空の編集画面を開いて新規作成（⌘N）")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.cardBg)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: status / error banner
    @ViewBuilder private func statusBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(msg).font(.system(size: 12)).foregroundColor(Theme.textPrimary)
            Spacer()
            Button { state.statusMessage = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textTertiary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.orange.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: active filter
    private var activeFilterRow: some View {
        HStack(spacing: 6) {
            Text("フィルタ:").font(.caption).foregroundColor(Theme.textSecondary)
            FlowLayout {
                ForEach(state.activeTags, id: \.self) { t in
                    TagChip(name: t, active: true) { state.toggleTag(t) }
                }
            }
            Spacer()
            Button("clear filter") { state.clearFilter() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(Theme.accent)
        }
    }

    // MARK: tag cloud
    private var tagCloud: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAGS").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.textTertiary)
            FlowLayout {
                ForEach(state.tags.prefix(60)) { tag in
                    TagChip(name: tag.name,
                            active: state.activeTags.contains(tag.name),
                            count: tag.count) {
                        state.toggleTag(tag.name)
                    }
                }
            }
        }
    }

    // MARK: cards
    private var recentHeader: some View {
        HStack {
            Text(state.activeTags.isEmpty && state.freeText.isEmpty ? "最近更新されたページ" : "結果")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            Text("\(state.cards.count)").font(.caption).foregroundColor(Theme.textTertiary)
            Spacer()
            Picker("", selection: $state.sort) {
                Text("更新順").tag("updated")
                Text("作成順").tag("created")
                Text("タイトル").tag("title")
            }
            .pickerStyle(.menu).frame(width: 110)
            .onChange(of: state.sort) { _ in Task { await state.search() } }
        }
    }

    private var cardGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(state.cards) { card in
                PageCardView(card: card)
                    .onTapGesture { Task { await state.open(card.id) } }
            }
        }
    }
}

/// A single page card: title, type, 2–4 tags, 1-line summary, author/year.
struct PageCardView: View {
    @EnvironmentObject var state: AppState
    let card: PageCard
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailView                        // edge-to-edge image (only if available)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: PageTypeStyle.symbol(card.type))
                        .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                    Text(card.title).font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary).lineLimit(2)
                }
                if !card.summary_ja.isEmpty {
                    Text(card.summary_ja).font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary).lineLimit(2)
                }
                if !card.tags.isEmpty {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(card.tags.prefix(4), id: \.self) { t in
                            TagChip(name: t) { state.toggleTag(t) }
                        }
                    }
                }
                if !card.authors.isEmpty || card.year != nil {
                    Text(metaLine).font(.system(size: 10)).foregroundColor(Theme.textTertiary)
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hover ? Theme.cardBgHover : Theme.cardBg)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hover = $0 }
    }

    // Thumbnail: video frame / og:image / PDF page. Collapses to nothing if absent or it fails to load.
    @ViewBuilder private var thumbnailView: some View {
        if let url = thumbURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity).frame(height: 130).clipped()
                case .empty:
                    Rectangle().fill(Theme.cardBgHover).frame(height: 130)
                        .overlay(ProgressView().controlSize(.small))
                default:
                    EmptyView()        // failure -> show nothing
                }
            }
        }
    }

    private var thumbURL: URL? {
        guard let t = card.thumbnail, !t.isEmpty else { return nil }
        if t.hasPrefix("http") { return URL(string: t) }
        var base = state.serverURLString
        if base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/\(t)")     // resolve "files/<name>" against server
    }

    private var metaLine: String {
        var parts: [String] = []
        if !card.authors.isEmpty { parts.append(card.authors.prefix(2).joined(separator: ", ")) }
        if let y = card.year { parts.append(String(y)) }
        return parts.joined(separator: " · ")
    }
}
