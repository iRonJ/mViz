import AVFoundation
import Observation
import SwiftUI

@main
struct mVizApp: App {
  @State private var model = VisualizerModel()

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
        .task {
          #if DEBUG
            await AudioAPIDiagnostics.runControlIfRequested()
            await AudioAPIDiagnostics.runCloudAnalysisIfRequested()
            if ProcessInfo.processInfo.arguments.contains("--music-library-control") {
              await model.library.loadMusicLibrary()
              let report =
                "songs=\(model.library.librarySongs.count), loading=\(model.library.loadingLibrary)\n\(model.library.libraryMessage)"
              let directory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask)[0]
              try? report.write(
                to: directory.appendingPathComponent("music-library-control.txt"), atomically: true,
                encoding: .utf8)
            }
          #endif
        }
    }
    .defaultSize(width: 560, height: 740)

    ImmersiveSpace(id: "ImmersiveSpace") {
      ImmersiveView(model: model)
    }
    .immersionStyle(selection: $model.immersionStyle, in: .mixed, .full)
  }
}
