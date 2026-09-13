import SwiftUI

struct ContentView: View {
  @Bindable var model: VisualizerModel
  @Environment(\.openImmersiveSpace) private var openSpace
  @Environment(\.dismissImmersiveSpace) private var dismissSpace
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Label("mViz", systemImage: "waveform.path")
          .font(.largeTitle.bold())
        Text("Step inside your music.")
          .font(.title2)
        Text(
          "An orbiting nebula of light. Bass drives the pulse, mids shape the motion, and highs scatter the stars."
        )
        .foregroundStyle(.secondary)
        VUMeterView(model: model)
        Button(
          model.listening ? "Stop microphone" : "Start microphone",
          systemImage: model.listening ? "mic.fill" : "mic"
        ) {
          if model.listening { model.stopListening() } else { Task { await model.start() } }
        }
        Text(model.status).font(.callout).foregroundStyle(.secondary)
        VisualizerControls(model: model)
        VStack(alignment: .leading) {
          Text("Sensitivity")
          Slider(value: $model.sensitivity, in: 0.5...10)
          Text("Particle intensity")
          Slider(value: $model.intensity, in: 0.2...1)
        }
        Button(model.isImmersed ? "Leave visualizer" : "Enter visualizer", systemImage: "sparkles")
        {
          Task { @MainActor in
            model.transitioning = true
            defer { model.transitioning = false }
            if model.isImmersed {
              await dismissSpace()
            } else {
              switch await openSpace(id: "ImmersiveSpace") {
              case .opened:
                model.isImmersed = true
                dismissWindow(id: "main")
              case .userCancelled: break
              case .error: model.status = "Couldn’t open the immersive space. Please try again."
              @unknown default: break
              }
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.transitioning)
        Divider()
        PlaylistView(model: model, player: model.library)
        Text(
          "Microphone mode hears your surroundings. Play music on nearby speakers. Audio stays on this device."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      .padding(32)
    }
    .onChange(of: model.isImmersed) { _, isImmersed in
      if isImmersed {
        dismissWindow(id: "main")
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background && !model.isImmersed { model.stop() }
    }
  }
}
