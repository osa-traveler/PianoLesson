# PianoPractice

個人用の iPad ピアノ練習アプリ。MusicXML の楽譜を、大譜表・落下レーン・鍵盤の3段で表示する。
落下レーンには五線（ト音・ヘ音の各5本線）を縦線として通し、譜面の音と鍵盤の位置をつなぐ。

- 仕様: [Docs/PianoPractice_SPEC.md](Docs/PianoPractice_SPEC.md)
- 実装計画: [Docs/IMPLEMENTATION_PLAN.md](Docs/IMPLEMENTATION_PLAN.md)

## ビルド

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # 自分の DEVELOPMENT_TEAM を書く
xcodegen generate
open PianoPractice.xcodeproj
```

ロジックのテスト: `cd Packages/PianoCore && swift test`

要件: Xcode 27 以降、iPadOS 26 以降。
