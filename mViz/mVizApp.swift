import AVFoundation
import Observation
import SwiftUI

@main
struct mVizApp: App {
  @State private var model = VisualizerModel()


  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
    }
    .defaultSize(width: 560, height: 740)

    ImmersiveSpace(id: "ImmersiveSpace") {
      ImmersiveView(model: model)
    }
    .immersionStyle(selection: $model.immersionStyle, in: .mixed, .full)
  }
}
