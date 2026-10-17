import PianoCore
import SwiftUI

/// 譜面ビュー（仕様 5章）。4小節ずつのページで表示し、切り替え時は横にスライドする。
struct ScoreCanvas: View {
    let score: Score
    let engraving: EngravedScore
    let beat: Double
    let settings: PracticeSettings
    /// ドラッグ中は表示するページを固定する
    var fixedPage: Int?

    var body: some View {
        Canvas { context, size in
            let geo = ScoreGeometry(size: size)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.panel))
            let paging = fixedPage.map { (page: $0, slide: Double?.none) }
                ?? ScorePaging.state(score: score, beat: beat, rate: settings.tempoRatio)
            if let slide = paging.slide {
                let t = 1 - pow(1 - slide, 3)
                var previous = context
                previous.translateBy(x: -t * size.width, y: 0)
                renderer(geo, page: paging.page - 1).draw(&previous)
                var current = context
                current.translateBy(x: (1 - t) * size.width, y: 0)
                renderer(geo, page: paging.page).draw(&current)
            } else {
                renderer(geo, page: paging.page).draw(&context)
            }
            if settings.showStaffGuides {
                drawStaffLabels(&context, geo: geo, page: paging.page)
            }
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                         with: .color(Theme.rule))
        }
    }

    private func renderer(_ geo: ScoreGeometry, page: Int) -> ScorePageRenderer {
        ScorePageRenderer(score: score, engraving: engraving, geo: geo, beat: beat,
                          settings: settings, page: page)
    }

    /// 五線の左端に線ごとの音名（ト音 = 右手の色、ヘ音 = 左手の色）
    private func drawStaffLabels(_ context: inout GraphicsContext, geo: ScoreGeometry, page: Int) {
        let index = page * ScoreGeometry.measuresPerPage
        guard engraving.measures.indices.contains(index) else { return }
        let clefs = engraving.measures[index].clefs
        for (staff, hand) in [(1, Hand.right), (2, Hand.left)] {
            guard let clef = clefs[staff] else { continue }
            let bottom = clef.bottomLineDiatonic
            for line in 0..<5 {
                let d = bottom + line * 2
                let spelling = Spelling(step: Step(rawValue: ((d % 7) + 7) % 7)!, octave: d / 7)
                context.draw(Text(NoteNaming.name(spelling, settings.naming))
                                .font(.ui(10, .bold)).foregroundStyle(Theme.hand(hand)),
                             at: CGPoint(x: 23 * geo.sx, y: geo.y(diatonic: d, staff: staff, bottomDiatonic: bottom)),
                             anchor: .center)
            }
        }
    }
}

/// 1ページ（4小節）ぶんの描画
private struct ScorePageRenderer {
    let score: Score
    let engraving: EngravedScore
    let geo: ScoreGeometry
    let beat: Double
    let settings: PracticeSettings
    let page: Int

    private let glyphs = MusicGlyphs.shared
    private var G: CGFloat { geo.space }
    private var headWidth: CGFloat { 1.32 * G }
    private var headHeight: CGFloat { 0.92 * G }
    private var stemWidth: CGFloat { 1.4 * geo.scale }
    private var lineWidth: CGFloat { max(1, geo.scale) }

    private var measureIndices: Range<Int> {
        let first = page * ScoreGeometry.measuresPerPage
        return first..<min(first + ScoreGeometry.measuresPerPage, engraving.measures.count)
    }

    func draw(_ context: inout GraphicsContext) {
        let indices = measureIndices
        guard !indices.isEmpty else { return }
        drawHighlight(&context)
        drawStaves(&context, measureCount: indices.count, isLastPage: indices.upperBound == engraving.measures.count)
        drawPageStart(&context, measure: engraving.measures[indices.lowerBound])

        var chordGeoms: [Int: ChordGeom] = [:]
        for (slot, mi) in indices.enumerated() {
            let m = engraving.measures[mi]
            if slot > 0 { drawClefChanges(&context, measure: m, slot: slot) }
            context.draw(Text(m.number).font(.ui(11)).foregroundStyle(Theme.subLight),
                         at: CGPoint(x: geo.measureX(slot: slot) + 3, y: geo.systemTop - 3), anchor: .bottomLeading)
            var geoms = layoutChords(measure: m, slot: slot)
            applyBeams(measure: m, geoms: &geoms)
            for c in m.chords { if let g = geoms[c.id] { chordGeoms[c.id] = g } }
            drawRests(&context, measure: m, slot: slot)
            for c in m.chords {
                if let g = geoms[c.id] { drawChord(&context, chord: c, geom: g, measure: m) }
            }
            drawBeams(&context, measure: m, geoms: geoms)
        }
        drawTies(&context, geoms: chordGeoms)
        drawPlayhead(&context)
    }

    // MARK: - 色

    private func colors(start: Double, end: Double, hand: Hand) -> (Color, Color?) {
        if !settings.hands.practices(hand) { return (Theme.otherHand, nil) }
        if end <= beat { return (Theme.played, nil) }
        if start <= beat { return (Theme.hand(hand), Theme.tint(hand)) }
        return (Theme.ink, nil)
    }

    // MARK: - 五線・小節線・記号

    private func currentSlot() -> Int? {
        guard beat >= 0, beat < score.lengthBeats else { return nil }
        let mi = score.measureIndex(atBeat: beat)
        return measureIndices.contains(mi) ? mi - measureIndices.lowerBound : nil
    }

    private func drawHighlight(_ context: inout GraphicsContext) {
        guard let slot = currentSlot() else { return }
        let rect = CGRect(x: geo.measureX(slot: slot), y: geo.systemTop,
                          width: geo.measureWidth, height: geo.systemBottom - geo.systemTop)
        context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(Theme.measureHi))
    }

    private func drawPlayhead(_ context: inout GraphicsContext) {
        guard let slot = currentSlot() else { return }
        let m = engraving.measures[measureIndices.lowerBound + slot]
        let fraction = m.lengthBeats > 0 ? min(max((beat - m.startBeat) / m.lengthBeats, 0), 1) : 0
        let x = geo.x(slot: slot, fraction: fraction)
        context.fill(Path(CGRect(x: x - 1, y: geo.systemTop, width: 2, height: geo.systemBottom - geo.systemTop)),
                     with: .color(Theme.ink))
        context.fill(Path(ellipseIn: CGRect(x: x - 5, y: geo.systemTop - 5, width: 10, height: 10)),
                     with: .color(Theme.ink))
    }

    private func drawStaves(_ context: inout GraphicsContext, measureCount: Int, isLastPage: Bool) {
        let left = geo.staffLeft
        let right = geo.measureX(slot: measureCount)
        for staff in [1, 2] {
            for line in 0..<5 {
                let y = geo.bottomLineY(staff: staff) - CGFloat(line) * G
                context.fill(Path(CGRect(x: left, y: y - lineWidth / 2, width: right - left, height: lineWidth)),
                             with: .color(Theme.staff))
            }
        }
        let top = geo.topLineY(staff: 1)
        let height = geo.bottomLineY(staff: 2) - top
        context.fill(Path(CGRect(x: left, y: top, width: 1.5 * geo.scale, height: height)), with: .color(Theme.staff))
        for slot in 1...measureCount {
            let x = geo.measureX(slot: slot)
            if slot == measureCount, isLastPage {
                let thick: CGFloat = 3
                context.fill(Path(CGRect(x: x - thick, y: top, width: thick, height: height)), with: .color(Theme.staff))
                context.fill(Path(CGRect(x: x - thick - 0.5 * G - lineWidth, y: top, width: lineWidth, height: height)),
                             with: .color(Theme.staff))
            } else {
                context.fill(Path(CGRect(x: x - lineWidth / 2, y: top, width: lineWidth * 1.2, height: height)),
                             with: .color(Theme.staff))
            }
        }
    }

    private func clefGlyph(_ clef: Clef) -> UInt32 {
        switch clef.sign {
        case .g: SMuFL.gClef
        case .f: SMuFL.fClef
        default: SMuFL.cClef
        }
    }

    /// 音部記号の基準点の y（ト音記号は第2線、ヘ音記号は第4線）
    private func clefY(_ clef: Clef, staff: Int) -> CGFloat {
        geo.bottomLineY(staff: staff) - CGFloat(clef.line - 1) * G
    }

    /// ページ左端の音部記号・調号・拍子記号
    private func drawPageStart(_ context: inout GraphicsContext, measure m: EngravedMeasure) {
        let clefX = geo.staffLeft + 6 * geo.sx
        var keyX = clefX
        for staff in [1, 2] {
            guard let clef = m.clefs[staff] else { continue }
            let code = clefGlyph(clef)
            glyphs.draw(code, at: CGPoint(x: clefX, y: clefY(clef, staff: staff)), space: G, color: Theme.ink, in: &context)
            keyX = max(keyX, clefX + glyphs.bounds(code).maxX * G + 0.8 * G)
        }

        let timeX = geo.firstMeasureX - 38 * geo.sx
        let showTime = page == 0 || m.timeChanged
        if m.key.fifths != 0 {
            let code = m.key.fifths > 0 ? SMuFL.sharp : SMuFL.flat
            let count = abs(m.key.fifths)
            let width = glyphs.bounds(code).width * G
            let available = (showTime ? timeX - 0.4 * G : geo.firstMeasureX - 0.6 * G) - keyX
            let step = min(width + 0.15 * G, available / CGFloat(count))
            for staff in [1, 2] {
                guard let clef = m.clefs[staff] else { continue }
                for (i, d) in m.key.accidentalDiatonics(clef: clef).enumerated() {
                    let y = geo.y(diatonic: d, staff: staff, bottomDiatonic: clef.bottomLineDiatonic)
                    glyphs.draw(code, at: CGPoint(x: keyX + CGFloat(i) * step, y: y), space: G, color: Theme.ink, in: &context)
                }
            }
        }

        if showTime {
            for staff in [1, 2] {
                let bottom = geo.bottomLineY(staff: staff)
                drawTimeNumber(&context, m.time.beats, centerX: timeX + G, y: bottom - 3 * G)
                drawTimeNumber(&context, m.time.beatType, centerX: timeX + G, y: bottom - G)
            }
        }
    }

    private func drawTimeNumber(_ context: inout GraphicsContext, _ value: Int, centerX: CGFloat, y: CGFloat) {
        let digits = String(value).compactMap { $0.wholeNumberValue }
        let widths = digits.map { glyphs.bounds(SMuFL.timeSigDigit($0)).width * G }
        var x = centerX - widths.reduce(0, +) / 2
        for (digit, w) in zip(digits, widths) {
            let code = SMuFL.timeSigDigit(digit)
            let b = glyphs.bounds(code)
            glyphs.draw(code, at: CGPoint(x: x - b.minX * G, y: y - b.midY * G), space: G, color: Theme.ink, in: &context)
            x += w
        }
    }

    private func drawClefChanges(_ context: inout GraphicsContext, measure m: EngravedMeasure, slot: Int) {
        for staff in m.clefChanged.sorted() {
            guard let clef = m.clefs[staff] else { continue }
            let small = G * 0.75
            let y = clefY(clef, staff: staff)
            glyphs.draw(clefGlyph(clef), at: CGPoint(x: geo.measureX(slot: slot) + 3, y: y), space: small,
                        color: Theme.ink, in: &context)
        }
    }

    // MARK: - 音符

    struct ChordGeom {
        var x: CGFloat           // 符頭（ずらしていない列）の中心
        var stemX: CGFloat
        var stemStart: CGFloat   // 符頭側の端
        var stemEnd: CGFloat     // 先端
        var headYs: [CGFloat]
        var bottom: Int          // 第1線の全音階番号
        var staff: Int
    }

    private func bottomDiatonic(_ m: EngravedMeasure, staff: Int) -> Int {
        m.clefs[staff]?.bottomLineDiatonic ?? (staff == 1 ? 30 : 18)
    }

    private func noteX(_ m: EngravedMeasure, slot: Int, offset: Double) -> CGFloat {
        geo.x(slot: slot, fraction: m.lengthBeats > 0 ? offset / m.lengthBeats : 0)
    }

    private func layoutChords(measure m: EngravedMeasure, slot: Int) -> [Int: ChordGeom] {
        var result: [Int: ChordGeom] = [:]
        let stemLength = 3.4 * G
        for c in m.chords {
            let bottom = bottomDiatonic(m, staff: c.staff)
            let ys = c.heads.map { geo.y(diatonic: $0.diatonic, staff: c.staff, bottomDiatonic: bottom) }
            let x = noteX(m, slot: slot, offset: c.offsetBeats)
            let lowY = ys.max() ?? 0
            let highY = ys.min() ?? 0
            let middleY = geo.y(diatonic: bottom + 4, staff: c.staff, bottomDiatonic: bottom)
            let extra = c.flagCount > 1 ? CGFloat(c.flagCount - 1) * 0.75 * G : 0
            let stemX = c.stemUp ? x + headWidth / 2 - stemWidth / 2 : x - headWidth / 2 + stemWidth / 2
            let start = c.stemUp ? lowY : highY
            let end = c.stemUp ? min(highY - stemLength - extra, middleY) : max(lowY + stemLength + extra, middleY)
            result[c.id] = ChordGeom(x: x, stemX: stemX, stemStart: start, stemEnd: end, headYs: ys,
                                     bottom: bottom, staff: c.staff)
        }
        return result
    }

    /// 連桁の傾きを決め、符幹の先端を連桁に揃える
    private func applyBeams(measure m: EngravedMeasure, geoms: inout [Int: ChordGeom]) {
        for beam in m.beams {
            let items = beam.chordIDs.compactMap { geoms[$0] }
            guard items.count >= 2, let first = items.first, let last = items.last else { continue }
            let x0 = first.stemX, x1 = last.stemX
            let dy = min(max(last.stemEnd - first.stemEnd, -G), G)
            func lineY(_ x: CGFloat) -> CGFloat { x1 == x0 ? first.stemEnd : first.stemEnd + dy * (x - x0) / (x1 - x0) }
            var shift: CGFloat = 0
            for g in items {
                shift = beam.stemUp ? max(shift, lineY(g.stemX) - g.stemEnd) : max(shift, g.stemEnd - lineY(g.stemX))
            }
            for id in beam.chordIDs {
                guard var g = geoms[id] else { continue }
                g.stemEnd = lineY(g.stemX) + (beam.stemUp ? -shift : shift)
                geoms[id] = g
            }
        }
    }

    private func drawChord(_ context: inout GraphicsContext, chord c: EngravedChord, geom g: ChordGeom,
                           measure m: EngravedMeasure) {
        let (chordColor, _) = colors(start: c.startBeat, end: c.endBeat, hand: c.hand)
        let shiftDX = (headWidth - stemWidth) * (c.stemUp ? 1 : -1)
        let headXs = c.heads.map { g.x + ($0.shifted ? shiftDX : 0) }

        // 加線
        let topD = c.heads.map(\.diatonic).max() ?? 0
        let lowD = c.heads.map(\.diatonic).min() ?? 0
        let ledgerLeft = (headXs.min() ?? g.x) - headWidth / 2 - 0.4 * G
        let ledgerRight = (headXs.max() ?? g.x) + headWidth / 2 + 0.4 * G
        var ledgers: [Int] = []
        if topD >= g.bottom + 10 { ledgers += Array(stride(from: g.bottom + 10, through: topD, by: 2)) }
        if lowD <= g.bottom - 2 { ledgers += Array(stride(from: g.bottom - 2, through: lowD, by: -2)) }
        for d in ledgers {
            let y = geo.y(diatonic: d, staff: g.staff, bottomDiatonic: g.bottom)
            context.fill(Path(CGRect(x: ledgerLeft, y: y - lineWidth * 0.6, width: ledgerRight - ledgerLeft,
                                     height: lineWidth * 1.2)), with: .color(Theme.staff))
        }

        // 符頭（発音中は薄色のハロー）
        for (i, head) in c.heads.enumerated() {
            let (color, halo) = colors(start: head.startBeat, end: head.endBeat, hand: c.hand)
            let center = CGPoint(x: headXs[i], y: g.headYs[i])
            if let halo {
                context.fill(headPath(center: center, grow: 0.35 * G), with: .color(halo))
            }
            if c.noteType.isHollow {
                let lw = max(1.6, 0.16 * G)
                context.stroke(headPath(center: center, grow: -lw / 2), with: .color(color), lineWidth: lw)
            } else {
                context.fill(headPath(center: center, grow: 0), with: .color(color))
            }
        }

        // 臨時記号
        let leftEdge = (headXs.min() ?? g.x) - headWidth / 2
        let sharpWidth = glyphs.bounds(SMuFL.sharp).width * G
        for (i, head) in c.heads.enumerated() {
            guard let acc = head.accidental else { continue }
            let code = acc.glyph
            let b = glyphs.bounds(code)
            let right = leftEdge - 0.3 * G - CGFloat(head.accidentalColumn) * (sharpWidth + 0.25 * G)
            let (color, _) = colors(start: head.startBeat, end: head.endBeat, hand: c.hand)
            glyphs.draw(code, at: CGPoint(x: right - b.maxX * G, y: g.headYs[i]), space: G, color: color, in: &context)
        }

        // 付点
        if c.dots > 0 {
            let rightEdge = (headXs.max() ?? g.x) + headWidth / 2
            for (i, head) in c.heads.enumerated() {
                let onLine = (head.diatonic - g.bottom) % 2 == 0
                let y = g.headYs[i] - (onLine ? geo.halfSpace : 0)
                for k in 0..<c.dots {
                    let x = rightEdge + 0.35 * G + CGFloat(k) * 0.5 * G
                    let r = 0.2 * G
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(chordColor))
                }
            }
        }

        // 符幹と旗
        guard c.noteType.hasStem else { return }
        let top = min(g.stemStart, g.stemEnd), bottom = max(g.stemStart, g.stemEnd)
        context.fill(Path(CGRect(x: g.stemX - stemWidth / 2, y: top, width: stemWidth, height: bottom - top)),
                     with: .color(chordColor))
        if c.flagCount > 0 {
            glyphs.draw(SMuFL.flag(count: c.flagCount, up: c.stemUp),
                        at: CGPoint(x: g.stemX - stemWidth / 2, y: g.stemEnd), space: G, color: chordColor, in: &context)
        }
    }

    /// 符頭の楕円（−18°回転）。grow で外側に広げる。
    private func headPath(center: CGPoint, grow: CGFloat) -> Path {
        let w = headWidth + 2 * grow, h = headHeight + 2 * grow
        return Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            .applying(CGAffineTransform(rotationAngle: -18 * .pi / 180)
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
    }

    private func drawBeams(_ context: inout GraphicsContext, measure m: EngravedMeasure, geoms: [Int: ChordGeom]) {
        let thickness = 0.5 * G
        let gap = 0.25 * G
        for beam in m.beams {
            let chords = beam.chordIDs.compactMap { id in m.chords.first { $0.id == id } }
            let items = chords.compactMap { geoms[$0.id] }
            guard items.count == chords.count, items.count >= 2 else { continue }
            let practiced = chords.contains { settings.hands.practices($0.hand) }
            let color: Color = !practiced ? Theme.otherHand
                : (chords.last!.endBeat <= beat ? Theme.played : Theme.ink)
            let dir: CGFloat = beam.stemUp ? 1 : -1  // 符頭へ向かう向き

            func segment(_ a: ChordGeom, _ b: ChordGeom, level: Int, from xa: CGFloat, to xb: CGFloat) {
                let slope = b.stemX == a.stemX ? 0 : (b.stemEnd - a.stemEnd) / (b.stemX - a.stemX)
                let off = dir * CGFloat(level) * (thickness + gap)
                let ya = a.stemEnd + slope * (xa - a.stemX) + off
                let yb = a.stemEnd + slope * (xb - a.stemX) + off
                var p = Path()
                p.move(to: CGPoint(x: xa, y: ya))
                p.addLine(to: CGPoint(x: xb, y: yb))
                p.addLine(to: CGPoint(x: xb, y: yb + dir * thickness))
                p.addLine(to: CGPoint(x: xa, y: ya + dir * thickness))
                p.closeSubpath()
                context.fill(p, with: .color(color))
            }

            let half = stemWidth / 2
            segment(items.first!, items.last!, level: 0, from: items.first!.stemX - half, to: items.last!.stemX + half)
            let maxLevel = chords.map(\.noteType.beamCount).max() ?? 1
            guard maxLevel > 1 else { continue }
            for level in 1..<maxLevel {
                for i in chords.indices where chords[i].noteType.beamCount > level {
                    let a = items[i]
                    if i + 1 < chords.count, chords[i + 1].noteType.beamCount > level {
                        segment(a, items[i + 1], level: level, from: a.stemX - half, to: items[i + 1].stemX + half)
                    } else if i == 0 || chords[i - 1].noteType.beamCount <= level {
                        // 単独の短い音: 鉤（最初なら右、それ以外は左）
                        let len = headWidth
                        let (xa, xb) = i == 0 ? (a.stemX - half, a.stemX + len) : (a.stemX - len, a.stemX + half)
                        segment(items[0], items[items.count - 1], level: level, from: xa, to: xb)
                    }
                }
            }
        }
    }

    private func drawRests(_ context: inout GraphicsContext, measure m: EngravedMeasure, slot: Int) {
        for r in m.rests {
            let bottom = bottomDiatonic(m, staff: r.staff)
            let type: NoteType = r.isMeasureRest ? .whole : r.noteType
            let code: UInt32
            var d = r.diatonic
            switch type {
            case .whole, .breve: code = SMuFL.restWhole; d += 2
            case .half: code = SMuFL.restHalf
            case .quarter: code = SMuFL.restQuarter
            case .eighth: code = SMuFL.rest8th
            case .sixteenth: code = SMuFL.rest16th
            case .thirtySecond: code = SMuFL.rest32nd
            case .sixtyFourth: code = SMuFL.rest64th
            }
            let cx = r.isMeasureRest ? geo.measureX(slot: slot) + geo.measureWidth / 2
                : noteX(m, slot: slot, offset: r.offsetBeats)
            let y = geo.y(diatonic: d, staff: r.staff, bottomDiatonic: bottom)
            let b = glyphs.bounds(code)
            let (color, _) = colors(start: r.startBeat, end: r.endBeat, hand: r.hand)
            glyphs.draw(code, at: CGPoint(x: cx - b.midX * G, y: y), space: G, color: color, in: &context)
            for k in 0..<r.dots {
                let x = cx + b.width * G / 2 + 0.35 * G + CGFloat(k) * 0.5 * G
                let rr = 0.2 * G
                context.fill(Path(ellipseIn: CGRect(x: x, y: y - geo.halfSpace - rr, width: 2 * rr, height: 2 * rr)),
                             with: .color(color))
            }
        }
    }

    private func drawTies(_ context: inout GraphicsContext, geoms: [Int: ChordGeom]) {
        let indices = measureIndices
        var ties: [EngravedTie] = []
        for mi in indices { ties += engraving.measures[mi].ties }
        // 前のページから入ってくるタイ
        if indices.lowerBound > 0 {
            ties += engraving.measures[indices.lowerBound - 1].ties.filter { $0.toChord.map { geoms[$0] != nil } ?? false }
        }
        let pageEnd = geo.measureX(slot: indices.count)
        for tie in ties {
            let from = geoms[tie.fromChord]
            let to = tie.toChord.flatMap { geoms[$0] }
            guard let anchor = from ?? to else { continue }
            let y = geo.y(diatonic: tie.diatonic, staff: anchor.staff, bottomDiatonic: anchor.bottom)
                + (tie.curveDown ? 0.6 : -0.6) * G
            let x1 = from.map { $0.x + headWidth * 0.6 } ?? geo.firstMeasureX - G
            let x2 = to.map { $0.x - headWidth * 0.6 } ?? pageEnd - 0.5 * G
            guard x2 > x1 else { continue }
            let dir: CGFloat = tie.curveDown ? 1 : -1
            let h = min(1.2 * G, max(0.5 * G, (x2 - x1) * 0.15))
            var p = Path()
            p.move(to: CGPoint(x: x1, y: y))
            p.addQuadCurve(to: CGPoint(x: x2, y: y), control: CGPoint(x: (x1 + x2) / 2, y: y + dir * h))
            p.addQuadCurve(to: CGPoint(x: x1, y: y), control: CGPoint(x: (x1 + x2) / 2, y: y + dir * (h - 0.25 * G)))
            p.closeSubpath()
            let chord = engraving.measures[max(0, indices.lowerBound - 1)...].lazy.flatMap(\.chords).first { $0.id == tie.fromChord }
            let color = chord.map { colors(start: $0.startBeat, end: $0.endBeat, hand: $0.hand).0 } ?? Theme.ink
            context.fill(p, with: .color(color))
        }
    }
}
