import SwiftUI
import AppKit

@main
struct ResearchAtlasApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Research Atlas") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新規ページ") { Task { await state.createNewPage() } }
                    .keyboardShortcut("n", modifiers: .command)
                Button("一覧へ戻る") { state.closePage() }
                    .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}

/// When launched via `swift run` (no app bundle) the process defaults to an
/// accessory app with no Dock icon / focus. Promote it to a regular app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        Group {
            if let page = state.openPage {
                PageDetailView(page: page)
            } else {
                HomeView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("サーバ設定").font(.headline)
            Text("FastAPI サーバの URL。ローカルは http://127.0.0.1:8000、自宅デスクトップは Tailscale IP（例: http://100.x.x.x:8000）。")
                .font(.caption).foregroundColor(.secondary)
            TextField("Server URL", text: $state.serverURLString)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("適用") {
                    Task { await state.applyServerURL() }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
