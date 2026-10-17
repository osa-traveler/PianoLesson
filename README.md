# PianoPractice

個人用の iPad ピアノ練習アプリ。MusicXML の楽譜を、大譜表・落下レーン・鍵盤の3段で表示する。
落下レーンには五線（ト音・ヘ音の各5本線）を縦線として通し、譜面の音と鍵盤の位置をつなぐ。

## ドキュメント

| 文書 | 内容 |
|---|---|
| [Docs/USER_GUIDE.md](Docs/USER_GUIDE.md) | 操作方法・実装済みの仕様（仕様書との違いを含む） |
| [Docs/STATUS.md](Docs/STATUS.md) | 作業状況・課題・実機での確認項目 |
| [Docs/WORKLOG.md](Docs/WORKLOG.md) | 作業ログ |
| [Docs/PianoPractice_SPEC.md](Docs/PianoPractice_SPEC.md) | 元の仕様書（デザイン案から起こしたもの） |
| [Docs/IMPLEMENTATION_PLAN.md](Docs/IMPLEMENTATION_PLAN.md) | 実装計画（前提・構成・フェーズ） |

## ビルド

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # 自分の DEVELOPMENT_TEAM を書く
./scripts/fetch-soundfont.sh                              # ピアノ音源（CC0）を取得
xcodegen generate
open PianoPractice.xcodeproj
```

ロジックのテスト: `cd Packages/PianoCore && swift test`

要件: Xcode 27 以降、iPadOS 26 以降。

## 同梱・利用している素材

- 楽譜フォント Bravura（Steinberg、SIL Open Font License 1.1）: `App/Resources/Fonts/`
- ピアノ音源 Upright Piano KW（FreePats、CC0 1.0）: `scripts/fetch-soundfont.sh` で取得（リポジトリには含めない）
