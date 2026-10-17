import PianoCore
import QuartzCore
import SwiftUI
import UIKit

/// 画面の鍵盤のタッチ入力（同時押し・指を滑らせての移動に対応）
struct KeyboardTouchView: UIViewRepresentable {
    let layout: KeyboardLayout
    let blackLength: CGFloat
    let onEvent: (KeyEvent) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.layout = layout
        view.blackLength = blackLength
        view.onEvent = onEvent
    }

    final class TouchView: UIView {
        var layout: KeyboardLayout?
        var blackLength: CGFloat = 92
        var onEvent: ((KeyEvent) -> Void)?
        private var keys: [ObjectIdentifier: Int] = [:]

        private func key(for touch: UITouch) -> Int? {
            layout?.key(at: touch.location(in: self), blackLength: blackLength)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                guard let midi = key(for: t) else { continue }
                keys[ObjectIdentifier(t)] = midi
                onEvent?(.down(midi: midi, velocity: 90, host: CACurrentMediaTime()))
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                let id = ObjectIdentifier(t)
                let midi = key(for: t)
                guard midi != keys[id] else { continue }
                let now = CACurrentMediaTime()
                if let old = keys[id] { onEvent?(.up(midi: old, host: now)) }
                keys[id] = midi
                if let midi { onEvent?(.down(midi: midi, velocity: 90, host: now)) }
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                if let midi = keys.removeValue(forKey: ObjectIdentifier(t)) {
                    onEvent?(.up(midi: midi, host: CACurrentMediaTime()))
                }
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchesEnded(touches, with: event)
        }
    }
}
