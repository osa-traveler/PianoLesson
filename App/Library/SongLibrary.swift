import Foundation
import Observation
import PianoCore

/// ライブラリの1曲。楽譜ファイルは Documents/Songs にコピーして持つ。
struct SongEntry: Codable, Identifiable {
    var id: UUID
    /// Documents/Songs 内のファイル名。nil なら内蔵の曲
    var fileName: String?
    var title: String
    var composer: String?
    var measureCount: Int
    var importedAt: Date
    var lastPracticedAt: Date?
    var settings = PracticeSettings()
    /// 最後の位置（拍）
    var lastBeat: Double?
    /// 通し練習ごとの正確さ（0…1）
    var accuracyHistory: [AccuracyRecord] = []

    static let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var isBuiltIn: Bool { fileName == nil }
}

struct AccuracyRecord: Codable, Hashable {
    var date: Date
    var accuracy: Double
    var tempoRatio: Double
    var hands: HandsMode
}

@MainActor @Observable
final class SongLibrary {
    private(set) var songs: [SongEntry] = []

    private let fileManager = FileManager.default
    private var documents: URL { URL.documentsDirectory }
    private var songsDirectory: URL { documents.appending(path: "Songs", directoryHint: .isDirectory) }
    private var indexURL: URL { documents.appending(path: "library.json") }

    init() {
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let list = try? JSONDecoder().decode([SongEntry].self, from: data) {
            songs = list
        }
        if !songs.contains(where: \.isBuiltIn) {
            let ode = SampleScores.odeToJoy
            songs.append(SongEntry(id: SongEntry.builtInID, fileName: nil, title: ode.title, composer: ode.composer,
                                   measureCount: ode.measures.count, importedAt: .distantPast))
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(songs).write(to: indexURL, options: .atomic)
        } catch {
            print("ライブラリを保存できません: \(error)")
        }
    }

    /// 最近練習した順（未練習は読み込んだ順）
    var sortedSongs: [SongEntry] {
        songs.sorted {
            ($0.lastPracticedAt ?? $0.importedAt) > ($1.lastPracticedAt ?? $1.importedAt)
        }
    }

    /// Files などから受け取ったファイルを取り込む。読み飛ばした内容を返す。
    func importFile(at url: URL) throws -> (SongEntry, [String]) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let baseName = url.deletingPathExtension().lastPathComponent
        let result = try MusicXMLImporter.load(data: data, fallbackTitle: baseName)

        try fileManager.createDirectory(at: songsDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let ext = url.pathExtension.isEmpty ? "musicxml" : url.pathExtension.lowercased()
        let fileName = "\(id.uuidString).\(ext)"
        try data.write(to: songsDirectory.appending(path: fileName), options: .atomic)

        let entry = SongEntry(id: id, fileName: fileName, title: result.score.title,
                              composer: result.score.composer, measureCount: result.score.measures.count,
                              importedAt: .now)
        songs.append(entry)
        save()
        // 共有メニューから受け取ったファイルは Documents/Inbox に置かれるので、コピー後に消す
        if url.path.contains("/Documents/Inbox/") { try? fileManager.removeItem(at: url) }
        return (entry, result.warnings)
    }

    func loadScore(for entry: SongEntry) throws -> Score {
        guard let fileName = entry.fileName else { return SampleScores.odeToJoy }
        let data = try Data(contentsOf: songsDirectory.appending(path: fileName))
        return try MusicXMLImporter.load(data: data, fallbackTitle: entry.title).score
    }

    func update(_ id: UUID, _ change: (inout SongEntry) -> Void) {
        guard let i = songs.firstIndex(where: { $0.id == id }) else { return }
        change(&songs[i])
        save()
    }

    func delete(_ entry: SongEntry) {
        guard !entry.isBuiltIn else { return }
        if let fileName = entry.fileName {
            try? fileManager.removeItem(at: songsDirectory.appending(path: fileName))
        }
        songs.removeAll { $0.id == entry.id }
        save()
    }
}
