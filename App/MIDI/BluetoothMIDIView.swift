import CoreAudioKit
import SwiftUI

/// Bluetooth MIDI 機器の検索・接続（Apple 標準の画面）
struct BluetoothMIDIView: UIViewControllerRepresentable {
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let central = CABTMIDICentralViewController()
        central.navigationItem.title = "Bluetooth MIDI"
        central.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done, primaryAction: UIAction { _ in onDone() })
        return UINavigationController(rootViewController: central)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
