import SwiftUI
import UniformTypeIdentifiers

/// Cosense-style page editor: a big body text area is the source of truth.
/// LLM results appear as "AI Suggestions" the user can Accept into the body.
struct PageDetailView: View {
    @EnvironmentObject var state: AppState
    let page: Page

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var type: String = "note"
    @State private var urlField: String = ""
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            editorColumn
            Divider().overlay(Theme.stroke)
            SidebarView(page: page).frame(width: 260)
        }
        .background(Theme.bg)
        .onAppear(perform: load)
        .onChange(of: page.id) { _ in load() }
    }

    private func load() {
        title = page.title; bodyText = page.body; type = page.type
    }

    // MARK: editor
    private var editorColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toolbar
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                sourceRow
                bodyEditor
                if let llm = page.llm { AISuggestionsView(llm: llm, currentBody: $bodyText) }
                translationPanel
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .onDrop(of: [.fileURL, .pdf], isTargeted: $dropTargeted) { handleDrop($0) }
        .overlay(dropTargeted ? Theme.accent.opacity(0.08) : .clear)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { state.closePage() } label: {
                Label("Home", systemImage: "chevron.left").font(.system(size: 12))
            }.buttonStyle(.plain).foregroundColor(Theme.accent)

            Picker("", selection: $type) {
                ForEach(PageTypeStyle.all, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).frame(width: 120)

            Spacer()

            Button { Task { await state.savePage(title: title, body: bodyText, type: type) } } label: {
                Text("保存").font(.system(size: 12, weight: .semibold))
            }.buttonStyle(.borderedProminent).tint(Theme.accent)

            Menu("AI") {
                Button("要約・タグ再解析") { Task { await state.reanalyze() } }
                Button("論文翻訳（章ごと）") { Task { await state.translate(full: false) } }
                Button("全文翻訳") { Task { await state.translate(full: true) } }
            }.frame(width: 60)
        }
    }

    private var sourceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link").foregroundColor(Theme.textTertiary).font(.system(size: 11))
                TextField("source: URL を貼り付け → Enter で解析", text: $urlField)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .foregroundColor(Theme.accent)
                    .onSubmit {
                        guard !urlField.isEmpty else { return }
                        Task { await state.submitURL(urlField); urlField = "" }
                    }
            }
            if let src = page.source_url, !src.isEmpty {
                Link(src, destination: URL(string: src) ?? URL(string: "about:blank")!)
                    .font(.system(size: 11)).foregroundColor(Theme.accent).lineLimit(1)
            }
            if let pdf = page.pdf_path {
                Label("PDF 添付済み (\(pdf))", systemImage: "doc.fill")
                    .font(.system(size: 11)).foregroundColor(Theme.textSecondary)
            }
            if state.isWorking, let msg = state.statusMessage {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(msg).font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(10)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BODY  —  #tag と [[内部リンク]] が自動抽出されます")
                .font(.system(size: 10, weight: .bold)).foregroundColor(Theme.textTertiary)
            TextEditor(text: $bodyText)
                .font(.system(size: 14, design: .default))
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 320)
                .padding(8)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: translation panel (papers)
    @ViewBuilder private var translationPanel: some View {
        if let llm = page.llm,
           !(llm.abstract_ja.isEmpty && llm.translation_ja.isEmpty && llm.section_summaries.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                Text("論文 日本語訳").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.tagFg)
                if !llm.abstract_ja.isEmpty {
                    labeled("Abstract", llm.abstract_ja)
                }
                ForEach(Array(llm.section_summaries.enumerated()), id: \.offset) { _, sec in
                    labeled(sec.heading, sec.summary)
                }
                if !llm.important_quotes.isEmpty {
                    Text("Important quotes").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textSecondary)
                    ForEach(llm.important_quotes, id: \.self) { q in
                        Text("“\(q)”").font(.system(size: 12)).italic().foregroundColor(Theme.textSecondary)
                    }
                }
                if !llm.translation_ja.isEmpty {
                    DisclosureGroup("全文翻訳") {
                        Text(llm.translation_ja).font(.system(size: 13)).foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                    }.tint(Theme.accent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func labeled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textSecondary)
            Text(text).font(.system(size: 13)).foregroundColor(Theme.textPrimary).textSelection(.enabled)
        }
    }

    // MARK: drag & drop
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.pathExtension.lowercased() == "pdf" else { return }
            Task { await state.uploadPDF(url) }
        }
        return true
    }
}

/// AI Suggestions block: tag chips you can add, summary/abstract you can insert.
/// The LLM never edits the body itself — Accept does the insertion.
struct AISuggestionsView: View {
    @EnvironmentObject var state: AppState
    let llm: LLMOutput
    @Binding var currentBody: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundColor(Theme.tagFg)
                Text("AI Suggestions").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.tagFg)
            }
            if !llm.suggested_tags.isEmpty {
                Text("タグ候補（クリックで追加）").font(.system(size: 10)).foregroundColor(Theme.textTertiary)
                FlowLayout {
                    ForEach(llm.suggested_tags, id: \.self) { t in
                        TagChip(name: t) { addTagToBody(t) }
                    }
                }
            }
            if !llm.summary_ja.isEmpty {
                suggestionRow(title: "要約を挿入", text: llm.summary_ja) {
                    insert("#summary\n\(llm.summary_ja)\n")
                }
            }
            if !llm.abstract_ja.isEmpty {
                suggestionRow(title: "Abstract訳を挿入", text: llm.abstract_ja) {
                    insert("#translation\n\(llm.abstract_ja)\n")
                }
            }
            if !llm.related_candidates.isEmpty {
                Text("関連ページ候補").font(.system(size: 10)).foregroundColor(Theme.textTertiary)
                FlowLayout {
                    ForEach(llm.related_candidates, id: \.self) { name in
                        Button { insert("[[\(name)]] ") } label: {
                            Text("[[\(name)]]").font(.system(size: 11)).foregroundColor(Theme.accent)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.accent.opacity(0.12)).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBg)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.tagFg.opacity(0.25)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func suggestionRow(title: String, text: String, accept: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textSecondary)
                Text(text).font(.system(size: 12)).foregroundColor(Theme.textPrimary).lineLimit(3)
            }
            Spacer()
            Button("Accept", action: accept).buttonStyle(.bordered).controlSize(.small).tint(Theme.tagFg)
        }
    }

    private func addTagToBody(_ tag: String) {
        if currentBody.contains("#\(tag)") { return }
        insert(currentBody.contains("#tags") ? " #\(tag)" : "\n#tags #\(tag)")
    }

    private func insert(_ text: String) {
        if !currentBody.isEmpty && !currentBody.hasSuffix("\n") { currentBody += "\n" }
        currentBody += text
    }
}
