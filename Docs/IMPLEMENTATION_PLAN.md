# 実装計画（PianoPractice_SPEC.md に基づく）

## 前提（2026-10-17 確定）

| 項目 | 内容 |
|---|---|
| 端末 | iPad Pro 13インチ（M4）。横向き 1376×1032pt。**譜面台に置いて使う**（目から 50〜70cm） |
| OS | iPadOS 26 以上のみ（Deployment Target 26.0） |
| 開発 | Xcode 27 / Swift 6 言語モード / XcodeGen（`project.yml`） |
| 音源 | 無料の SF2 を同梱（差し替えやすくしておく） |
| MIDI | 当面は USB（class compliant）。Bluetooth MIDI は後で追加 |
| サンプル | `Docs/sample.mxl`（Audiveris による OMR 出力。Voice＋Piano の2パート） |

### 13インチでの寸法

仕様の基準は 1194×834pt。13インチ（1376×1032）では次のように伸縮させる。

- トップバー 56pt、鍵盤 150pt は固定
- 残りの 826pt を譜面：レーン = 248：380 で分ける（譜面 ≈ 326、レーン ≈ 500）
- 譜面の五線間隔 G は `min(幅比, 高さ比) × 11pt`、横は幅比で伸ばす
- 譜面台に置く前提なので、文字や線は基準より小さくしない（可読性の確認を各 Phase に入れる）
- 練習中は自動ロックを無効にする（`isIdleTimerDisabled`）

### sample.mxl から分かったこと（パーサの要件）

OMR の出力なので、楽譜として不整合がある。止まらずに読めることが必須。

- 最初の小節に `<time>` が無い（13小節目で初めて 4/4 が出る）→ 拍子が無ければ 4/4 とみなす
- 小節の実際の長さが拍子と合わない（4/4 で 12〜24 単位、`divisions=4`）。右手と左手で長さが違う小節もある
  - 方針：小節長 = その小節で一番長い譜表の長さ。拍子より短ければ拍子の長さまで埋める（1小節目だけは弱起として短いままにする）
  - 不整合のある小節は読み込み後に一度だけ通知する
- 12小節目は左手（staff 2）が丸ごと無い
- パートは Voice（P1）と Piano（P2、`staves=2`）→ 仕様どおり `staves=2` の P2 を使う
- `harmony`、`lyric`、`print`、`direction`、`articulations` などは読み飛ばす（通知の対象にもしない）

## 構成

```
project.yml                 XcodeGen
App/                        iPad アプリ（SwiftUI）
  Views/                    PracticeScreen, TopBar, LaneCanvas, KeyboardCanvas, ScoreCanvas …
  Audio/ MIDI/ Library/
  Resources/                フォント、SF2
Packages/PianoCore/         UI 非依存のロジック（swift test で Mac 上でテスト）
  Model/ Timing/ Layout/ Naming/ MusicXML/ Judge/
```

時間の基準は「拍（四分音符 = 1.0）」。`PracticeClock` が「原曲時間（秒）」を進め、`TempoMap` で拍に変換する。
60fps の描画は 1つの `TimelineView` で現在の拍を1回だけ求め、譜面・レーン・鍵盤に同じ値を渡す。

## フェーズ

| Phase | 内容 | 確認条件 |
|---|---|---|
| 0 | 雛形：git、project.yml、PianoCore パッケージ、4段レイアウト | シミュレータで起動、`swift test` が通る |
| 1 | 鍵盤とレーン（歓喜の歌を直書き）、トップバーの再生系 | ノーツと鍵の中心が全鍵で一致、五線ガイドがノーツを貫く、60fps |
| 2 | 譜面ビュー（Bravura 同梱） | 判定ライン到達と同じフレームで譜面の音符が「発音中」になる |
| 3 | 音（SF2＋AVAudioUnitSampler、先読みスケジューラ、3系統の音量、片手の自動演奏） | テンポを変えても音と表示がずれない |
| 4 | MusicXML / .mxl 読み込み、曲ライブラリ | sample.mxl が崩れずに表示される。タイが1本のノーツになる |
| 5 | USB MIDI 入力、判定、待機モード、画面鍵盤のタッチ入力 | 和音を全部押したら次へ進む |
| 6 | 設定画面、曲ごとの設定保存、ループ範囲 | — |
| 7 | Bluetooth MIDI（`CABTMIDICentralViewController`） | — |
