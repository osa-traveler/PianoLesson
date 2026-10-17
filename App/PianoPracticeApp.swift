import PianoCore
import SwiftUI

@main
struct PianoPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}

/// ライブラリと練習画面の切り替え、読み込みの通知
struct AppRoot: View {
    @State private var library = SongLibrary()
    @State private var practice: PracticeModel?
    @State private var notice: Notice?
    @Environment(\.scenePhase) private var scenePhase

    struct Notice: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    var body: some View {
        Group {
            if let practice {
                PracticeScreen(model: practice, onBack: closePractice)
            } else {
                LibraryView(library: library, open: open, importFile: importFile)
            }
        }
        .onOpenURL { url in importFile(url) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { practice?.pause(); saveProgress() }
        }
        .alert(item: $notice) { n in
            Alert(title: Text(n.title), message: Text(n.message), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            AudioEngine.shared.start()
            openDebugScoreIfNeeded()
        }
    }

    private func open(_ song: SongEntry) {
        do {
            let score = try library.loadScore(for: song)
            practice = PracticeModel(score: score, songID: song.id, settings: song.settings, lastBeat: song.lastBeat)
        } catch {
            notice = Notice(title: "楽譜を開けません", message: error.localizedDescription)
        }
    }

    private func importFile(_ url: URL) {
        do {
            let (entry, warnings) = try library.importFile(at: url)
            if !warnings.isEmpty {
                notice = Notice(title: "「\(entry.title)」を読み込みました",
                                message: "一部は読み飛ばしています。\n\n" + warnings.map { "・" + $0 }.joined(separator: "\n"))
            }
            if practice == nil { open(entry) }
        } catch {
            notice = Notice(title: "読み込めませんでした", message: error.localizedDescription)
        }
    }

    private func saveProgress() {
        guard let practice else { return }
        let beat = practice.currentBeat
        library.update(practice.songID) {
            $0.settings = practice.settings
            $0.lastBeat = beat
            $0.lastPracticedAt = .now
        }
    }

    private func closePractice() {
        practice?.pause()
        saveProgress()
        AudioEngine.shared.detach()
        practice = nil
    }

    private func openDebugScoreIfNeeded() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "scorePath"), practice == nil,
           let data = FileManager.default.contents(atPath: path),
           let result = try? MusicXMLImporter.load(data: data, fallbackTitle: "sample") {
            practice = PracticeModel(score: result.score, songID: UUID())
        } else if defaults.bool(forKey: "openSample"), let song = library.songs.first(where: \.isBuiltIn) {
            open(song)
        }
        #endif
    }
}
