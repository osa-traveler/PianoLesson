import PianoCore
import SwiftUI

@main
struct PianoPracticeApp: App {
    @State private var model = PracticeModel(score: SampleScores.odeToJoy)

    var body: some Scene {
        WindowGroup {
            PracticeScreen(model: model)
        }
    }
}
