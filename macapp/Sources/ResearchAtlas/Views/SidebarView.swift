import SwiftUI

/// Right sidebar: Tags, Same Tags, Similar Pages, Backlinks.
struct SidebarView: View {
    @EnvironmentObject var state: AppState
    let page: Page

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Tags") {
                    if page.tags.isEmpty {
                        Text("タグなし").font(.caption).foregroundColor(Theme.textTertiary)
                    } else {
                        FlowLayout {
                            ForEach(page.tags, id: \.self) { t in
                                TagChip(name: t) { state.toggleTag(t); state.closePage() }
                            }
                        }
                    }
                }

                let sameTags = state.similar.filter { $0.reason == "same-tags" }
                section("Same Tags") {
                    pageList(sameTags)
                }

                let embed = state.similar.filter { $0.reason == "embedding" }
                section("Similar Pages") {
                    if embed.isEmpty {
                        Text("embedding 類似ページなし").font(.caption).foregroundColor(Theme.textTertiary)
                    } else {
                        pageList(embed)
                    }
                }

                section("Backlinks") {
                    if page.backlinks.isEmpty {
                        Text("被リンクなし").font(.caption).foregroundColor(Theme.textTertiary)
                    } else {
                        ForEach(page.backlinks, id: \.self) { t in
                            linkRow(t)
                        }
                    }
                }

                if !page.outgoing_links.isEmpty {
                    section("Links ([[...]])") {
                        ForEach(page.outgoing_links, id: \.self) { t in linkRow(t) }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.textTertiary)
            content()
        }
    }

    private func pageList(_ items: [SimilarPage]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                Text("該当なし").font(.caption).foregroundColor(Theme.textTertiary)
            }
            ForEach(items) { s in
                Button { Task { await state.open(s.id) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: PageTypeStyle.symbol(s.type))
                            .font(.system(size: 10)).foregroundColor(Theme.textTertiary)
                        Text(s.title).font(.system(size: 12)).foregroundColor(Theme.accent).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.2f", s.score))
                            .font(.system(size: 9)).foregroundColor(Theme.textTertiary)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    /// Backlinks / outgoing links are page titles. Open by title via search.
    private func linkRow(_ title: String) -> some View {
        Button {
            Task {
                if let card = state.cards.first(where: { $0.title == title }) {
                    await state.open(card.id)
                } else {
                    state.searchText = title
                    state.closePage()
                }
            }
        } label: {
            Text(title).font(.system(size: 12)).foregroundColor(Theme.accent).lineLimit(1)
        }.buttonStyle(.plain)
    }
}
