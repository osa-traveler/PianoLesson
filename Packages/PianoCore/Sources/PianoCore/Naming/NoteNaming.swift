public enum Naming: String, Codable, Sendable, CaseIterable {
    case cde, doremi
}

public enum NoteNaming {
    /// 譜面の表記に従った音名。includeOctave が true なら末尾にオクターブ番号（C4 など）。
    public static func name(_ spelling: Spelling, _ naming: Naming, includeOctave: Bool = false) -> String {
        let base: String
        switch naming {
        case .cde: base = spelling.step.letter
        case .doremi: base = ["ド", "レ", "ミ", "ファ", "ソ", "ラ", "シ"][spelling.step.rawValue]
        }
        let accidental: String
        switch spelling.alter {
        case 2: accidental = "𝄪"
        case 1: accidental = "♯"
        case -1: accidental = "♭"
        case -2: accidental = "𝄫"
        default: accidental = ""
        }
        return base + accidental + (includeOctave ? String(spelling.octave) : "")
    }

    /// 表記の情報が無い音（鍵盤など）の音名。C の鍵だけオクターブ番号を付ける。
    public static func keyName(midi: Int, _ naming: Naming) -> String {
        var sp = Spelling(midi: midi)
        if naming == .doremi, sp.step == .a, sp.alter == -1 {
            sp = Spelling(step: .g, alter: 1, octave: sp.octave)  // 仕様の表どおり ソ♯
        }
        let withOctave = sp.step == .c && sp.alter == 0
        return name(sp, naming, includeOctave: withOctave)
    }

    /// レーンのノーツ用。C だけオクターブ番号を付ける（鍵盤の表記に揃える）。
    public static func laneName(_ spelling: Spelling, _ naming: Naming) -> String {
        name(spelling, naming, includeOctave: spelling.step == .c && spelling.alter == 0)
    }
}
