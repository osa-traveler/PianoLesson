import PianoCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let musicXML = UTType(importedAs: "org.musicxml.musicxml")
    static let compressedMusicXML = UTType(importedAs: "com.recordare.musicxml.compressed")
}

/// 曲ライブラリ（仕様 9.2）
struct LibraryView: View {
    let library: SongLibrary
    let open: (SongEntry) -> Void
    let importFile: (URL) -> Void

    @State private var showingImporter = false
    @State private var pendingDelete: SongEntry?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("曲ライブラリ").font(.ui(22, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    showingImporter = true
                } label: {
                    Label("MusicXML を読み込む", systemImage: "square.and.arrow.down")
                        .font(.ui(15, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 72)
            .background(Theme.panel)
            .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(library.sortedSongs) { song in
                        SongRow(song: song) { open(song) }
                            .contextMenu {
                                if !song.isBuiltIn {
                                    Button("削除", systemImage: "trash", role: .destructive) { pendingDelete = song }
                                }
                            }
                    }
                    Text("Files アプリや他のアプリの共有メニューからも読み込めます（.musicxml / .xml / .mxl）。長押しで削除。")
                        .font(.ui(12))
                        .foregroundStyle(Theme.subLight)
                        .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .background(Theme.bg)
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.musicXML, .compressedMusicXML, .xml],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(importFile) }
        }
        .confirmationDialog("「\(pendingDelete?.title ?? "")」を削除しますか？",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let song = pendingDelete { library.delete(song) }
                pendingDelete = nil
            }
        }
    }
}

private struct SongRow: View {
    let song: SongEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: song.isBuiltIn ? "music.note" : "music.note.list")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.handR)
                    .frame(width: 48, height: 48)
                    .background(Theme.tintR, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.ui(17, .bold)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.ui(13)).foregroundStyle(Theme.sub)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(lastPracticed).font(.ui(13)).foregroundStyle(Theme.sub)
                    if let last = song.accuracyHistory.last {
                        Text("正確さ \(Int((last.accuracy * 100).rounded()))%").font(.ui(12, .bold)).foregroundStyle(Theme.handR)
                    }
                }
                Image(systemName: "chevron.right").foregroundStyle(Theme.subLight)
            }
            .padding(16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        [song.composer, "\(song.measureCount)小節", song.isBuiltIn ? "内蔵サンプル" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var lastPracticed: String {
        guard let date = song.lastPracticedAt else { return "未練習" }
        return "最後に練習: " + date.formatted(.relative(presentation: .named))
    }
}
