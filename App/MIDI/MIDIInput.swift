import CoreMIDI
import Observation
import QuartzCore
import Synchronization

/// 鍵盤からの入力（MIDI・画面の鍵盤のどちらも）
enum KeyEvent: Sendable {
    case down(midi: Int, velocity: UInt8, host: Double)
    case up(midi: Int, host: Double)
}

/// 入力の受け取り先（MIDI スレッドから読むのでロックで守る）
final class KeyEventHandler: Sendable {
    private let handler = Mutex<(@Sendable (KeyEvent) -> Void)?>(nil)

    func set(_ h: (@Sendable (KeyEvent) -> Void)?) { handler.withLock { $0 = h } }
    func send(_ event: KeyEvent) { handler.withLock { $0 }?(event) }
}

/// CoreMIDI の入力（USB。Bluetooth MIDI も接続済みなら同じように受け取れる）
@MainActor @Observable
final class MIDIInput {
    static let shared = MIDIInput()

    private(set) var sourceNames: [String] = []
    var isConnected: Bool { !sourceNames.isEmpty }

    /// MIDI スレッドから呼ばれる
    @ObservationIgnored let handler = KeyEventHandler()

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var port = MIDIPortRef()
    @ObservationIgnored private var connected: Set<MIDIEndpointRef> = []

    private init() {
        let status = MIDIClientCreateWithBlock("PianoPractice" as CFString, &client) { _ in
            Task { @MainActor in MIDIInput.shared.refresh() }
        }
        guard status == noErr else {
            print("MIDI クライアントを作れません: \(status)")
            return
        }
        let handler = self.handler
        let timebase: Double = {
            var info = mach_timebase_info_data_t()
            mach_timebase_info(&info)
            return Double(info.numer) / Double(info.denom) / 1e9
        }()
        MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &port) { list, _ in
            for packet in list.unsafeSequence() {
                let count = Int(packet.pointee.wordCount)
                let host = packet.pointee.timeStamp == 0 ? CACurrentMediaTime()
                    : Double(packet.pointee.timeStamp) * timebase
                withUnsafeBytes(of: packet.pointee.words) { raw in
                    let words = raw.bindMemory(to: UInt32.self)
                    for i in 0..<min(count, words.count) {
                        if let event = Self.parse(words[i], host: host) { handler.send(event) }
                    }
                }
            }
        }
        refresh()
    }

    /// UMP（MIDI 1.0 チャンネルボイス）の 1 ワードを読む
    nonisolated private static func parse(_ word: UInt32, host: Double) -> KeyEvent? {
        guard word >> 28 == 0x2 else { return nil }
        let status = (word >> 16) & 0xF0
        let note = Int((word >> 8) & 0x7F)
        let velocity = UInt8(word & 0x7F)
        switch status {
        case 0x90 where velocity > 0: return .down(midi: note, velocity: velocity, host: host)
        case 0x90, 0x80: return .up(midi: note, host: host)
        default: return nil
        }
    }

    /// 接続されている入力をすべてつなぐ
    func refresh() {
        var names: [String] = []
        var current: Set<MIDIEndpointRef> = []
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }
            current.insert(source)
            if !connected.contains(source) {
                MIDIPortConnectSource(port, source, nil)
            }
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name) == noErr,
               let n = name?.takeRetainedValue() {
                names.append(n as String)
            }
        }
        connected = current
        sourceNames = names
    }
}
