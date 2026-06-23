import SwiftUI
import UniformTypeIdentifiers
import AppKit
import WebKit

/// Dedicated page editor: 作品名 → 本文 → リンク → 動画埋め込み → PDF を上から並べる。
/// LLM results appear as "AI Suggestions" the user can Accept into the body.
struct PageDetailView: View {
    @EnvironmentObject var state: AppState
    let page: Page

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var type: String = "note"
    @State private var sourceURL: String = ""
    @State private var videoURL: String = ""
    @State private var dropTargeted = false
    @FocusState private var titleFocused: Bool

    // Autosave bookkeeping
    @State private var autosaveTask: Task<Void, Never>?
    @State private var savedSnapshot = ""        // last persisted field state
    @State private var openedPageID = ""         // id currently loaded into the fields
    @State private var saveState: SaveState = .idle
    private enum SaveState { case idle, saving, saved }
    private static let debounce: UInt64 = 900_000_000   // 0.9s

    var body: some View {
        HStack(spacing: 0) {
            editorColumn
            Divider().overlay(Theme.stroke)
            SidebarView(page: page).frame(width: 260)
        }
        .background(Theme.bg)
        .onAppear(perform: load)
        .onChange(of: page.id) { _ in load() }
        .onDisappear {
            // Leaving the editor: flush any pending edits to the page we had open.
            autosaveTask?.cancel()
            if snapshot() != savedSnapshot {
                let id = openedPageID.isEmpty ? page.id : openedPageID
                let fields = currentFields(fallbackTitle: page.title)
                Task { await state.autoSaveFields(pageID: id, fields: fields) }
            }
        }
    }

    private func snapshot() -> String {
        [title, bodyText, type, sourceURL, videoURL].joined(separator: "\u{1}")
    }

    /// PATCH body. Omits an empty title (keeps the server's existing one) and
    /// sends cleared URLs as null so they actually clear.
    private func currentFields(fallbackTitle: String) -> [String: Any] {
        var f: [String: Any] = ["body": bodyText, "type": type]
        let t = title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { f["title"] = title }
        else if !fallbackTitle.isEmpty { f["title"] = fallbackTitle }
        f["source_url"] = sourceURL.isEmpty ? NSNull() : sourceURL
        f["video_url"] = videoURL.isEmpty ? NSNull() : videoURL
        return f
    }

    private func load() {
        // Flush unsaved edits from the previously open page before swapping fields.
        if !openedPageID.isEmpty, openedPageID != page.id, snapshot() != savedSnapshot {
            let prevID = openedPageID
            let fields = currentFields(fallbackTitle: "")
            Task { await state.autoSaveFields(pageID: prevID, fields: fields) }
        }
        autosaveTask?.cancel()
        openedPageID = page.id
        // A freshly created page has a placeholder title: show an empty field
        // (with the prompt) and focus it so the user types the real name.
        let isPlaceholder = page.title.hasPrefix("無題 ")
        title = isPlaceholder ? "" : page.title
        bodyText = page.body
        type = page.type
        sourceURL = page.source_url ?? ""
        videoURL = page.video_url ?? ""
        savedSnapshot = snapshot()
        saveState = .idle
        if isPlaceholder { titleFocused = true }
    }

    /// Called on every edit: debounce, then save.
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard snapshot() != savedSnapshot else { return }   // unchanged (e.g. just loaded)
        saveState = .idle
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: Self.debounce)
            if Task.isCancelled { return }
            await commitSave()
        }
    }

    /// Save immediately (⌘S / Enter in title).
    private func saveNow() {
        autosaveTask?.cancel()
        Task { await commitSave() }
    }

    @MainActor private func commitSave() async {
        guard snapshot() != savedSnapshot else { return }
        let snap = snapshot()
        saveState = .saving
        await state.autoSaveFields(pageID: page.id, fields: currentFields(fallbackTitle: page.title))
        savedSnapshot = snap
        saveState = .saved
    }

    // MARK: editor
    private var editorColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                toolbar
                titleField                       // 1. 作品名
                bodyEditor                       // 2. 本文テキスト
                linkSection                      // 3. リンク貼り付け
                videoSection                     // 4. 動画リンク → 埋め込み
                pdfSection                       // 5. PDF 貼り付け
                if let llm = page.llm { AISuggestionsView(llm: llm, currentBody: $bodyText) }
                translationPanel
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: title) { _ in scheduleAutosave() }
        .onChange(of: bodyText) { _ in scheduleAutosave() }
        .onChange(of: type) { _ in scheduleAutosave() }
        .onChange(of: sourceURL) { _ in scheduleAutosave() }
        .onChange(of: videoURL) { _ in scheduleAutosave() }
        .onDrop(of: [.fileURL, .pdf], isTargeted: $dropTargeted) { handleDrop($0) }
        .overlay(dropTargeted
                 ? RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 2).padding(8)
                 : nil)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { state.closePage() } label: {
                Label("一覧へ", systemImage: "chevron.left").font(.system(size: 12))
            }.buttonStyle(.plain).foregroundColor(Theme.accent)
            .help("一覧に戻る（編集は自動保存されます）")

            Picker("", selection: $type) {
                ForEach(PageTypeStyle.all, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).frame(width: 120)

            if state.isWorking { ProgressView().controlSize(.small) }

            Spacer()

            saveStateView

            Menu("AI") {
                Button("要約・タグ再解析") { Task { await state.reanalyze() } }
                Button("論文翻訳（章ごと）") { Task { await state.translate(full: false) } }
                Button("全文翻訳") { Task { await state.translate(full: true) } }
            }.frame(width: 60)

            // Hidden ⌘S for an immediate save.
            Button("", action: saveNow).keyboardShortcut("s", modifiers: .command)
                .opacity(0).frame(width: 0)
        }
    }

    @ViewBuilder private var saveStateView: some View {
        switch saveState {
        case .saving:
            HStack(spacing: 4) { ProgressView().controlSize(.small)
                Text("保存中…").font(.system(size: 11)).foregroundColor(Theme.textTertiary) }
        case .saved:
            Label("保存済み", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundColor(Theme.tagFg)
        case .idle:
            Text("自動保存").font(.system(size: 11)).foregroundColor(Theme.textTertiary)
        }
    }

    // 1. 作品名
    private var titleField: some View {
        TextField("作品名・ページ名", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(Theme.textPrimary)
            .focused($titleFocused)
            .onSubmit { saveNow() }
    }

    // 2. 本文テキスト
    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("本文  —  #tag と [[内部リンク]] が自動抽出されます")
            TextEditor(text: $bodyText)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 280)
                .padding(8)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // 3. リンク貼り付け（source URL）— 貼って解析すると LLM が要約・タグを生成
    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("リンク（出典 URL）")
            HStack(spacing: 6) {
                Image(systemName: "link").foregroundColor(Theme.textTertiary).font(.system(size: 12))
                TextField("https://… を貼り付け", text: $sourceURL)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .foregroundColor(Theme.accent)
                if let url = URL(string: sourceURL), !sourceURL.isEmpty {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square").foregroundColor(Theme.accent)
                    }
                }
                Button("解析") {
                    guard !sourceURL.isEmpty else { return }
                    Task { await state.submitURL(sourceURL) }
                }
                .controlSize(.small)
                .disabled(sourceURL.isEmpty)
                .help("URL の本文を取得し、LLM で要約・タグ候補・翻訳を生成")
            }
            .padding(10)
            .background(Theme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // 4. 動画リンク → 埋め込み
    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("動画リンク")
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle").foregroundColor(Theme.textTertiary).font(.system(size: 12))
                TextField("YouTube / Vimeo の URL を貼り付け", text: $videoURL)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .foregroundColor(Theme.accent)
            }
            .padding(10)
            .background(Theme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let embed = VideoEmbed.url(from: videoURL) {
                WebView(url: embed)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if !videoURL.isEmpty {
                Text("※ 埋め込み対応は YouTube / Vimeo。その他はリンクとして保存されます。")
                    .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
            }
        }
    }

    // 5. PDF 貼り付け（ドラッグ&ドロップ or 選択）
    private var pdfSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("PDF")
            HStack(spacing: 10) {
                Button {
                    pickPDF()
                } label: {
                    Label("PDF を選択", systemImage: "doc.badge.plus").font(.system(size: 12))
                }.controlSize(.small)
                Text("またはこの画面に PDF をドラッグ&ドロップ")
                    .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                Spacer()
            }
            if let pdf = page.pdf_path {
                Label("添付済み: \(pdf)", systemImage: "doc.fill")
                    .font(.system(size: 11)).foregroundColor(Theme.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.textTertiary)
    }

    private func pickPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await state.uploadPDF(url) }
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

// MARK: - Video embedding

/// Converts a YouTube / Vimeo watch URL into an embeddable player URL.
enum VideoEmbed {
    static func url(from raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, let comps = URLComponents(string: s), let host = comps.host?.lowercased()
        else { return nil }

        // YouTube: youtu.be/<id>, youtube.com/watch?v=<id>, youtube.com/embed/<id>
        if host.contains("youtu.be") {
            let id = comps.path.split(separator: "/").last.map(String.init) ?? ""
            return id.isEmpty ? nil : URL(string: "https://www.youtube.com/embed/\(id)")
        }
        if host.contains("youtube.com") {
            if comps.path.hasPrefix("/embed/") { return URL(string: s) }
            if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value {
                return URL(string: "https://www.youtube.com/embed/\(v)")
            }
        }
        // Vimeo: vimeo.com/<id> -> player.vimeo.com/video/<id>
        if host.contains("vimeo.com") {
            let id = comps.path.split(separator: "/").last.map(String.init) ?? ""
            if let n = Int(id) { return URL(string: "https://player.vimeo.com/video/\(n)") }
        }
        return nil
    }
}

/// Embeds a video player by wrapping the player URL in an <iframe> inside an
/// HTML page whose baseURL is the player's host. Loading the embed URL as the
/// top-level frame is rejected by YouTube ("Video unavailable"); giving it a
/// proper origin via an iframe + baseURL is the reliable approach.
struct WebView: NSViewRepresentable {
    let url: URL          // embeddable player URL (…/embed/<id>, player.vimeo.com/…)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url

        // The parent page must be a NEUTRAL third-party origin (not youtube.com),
        // otherwise YouTube rejects the embed (e.g. error 152). example.com is a
        // reserved, always-valid origin and is never actually fetched here.
        let parentOrigin = "https://www.example.com"
        let src = url.absoluteString + (url.query == nil ? "?playsinline=1&rel=0" : "&playsinline=1&rel=0")
        let html = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
        iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe src="\(src)"
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          allowfullscreen></iframe></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: parentOrigin))
    }

    final class Coordinator { var loaded: URL? }
}
