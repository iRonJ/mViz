import RealityKit
import SwiftUI
import UIKit

struct ImmersiveView: View {
  var model: VisualizerModel
  @Environment(\.dismissImmersiveSpace) private var dismissSpace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showSettings = false
  @State private var field: ParticleField?
  @State private var updateSubscription: EventSubscription?

  var body: some View {
    RealityView { content, attachments in
      let visualizerField = field ?? ParticleField()
      if field == nil { field = visualizerField }
      content.add(visualizerField.root)
      content.add(visualizerField.stageRoot)
      if let controls = attachments.entity(for: "controls") {
        controls.position = [0, 1.1, -1.5]
        content.add(controls)
      }
      updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
        visualizerField.update(dt: Float(event.deltaTime), model: model)
      }
    } attachments: {
      Attachment(id: "controls") {
        VStack(spacing: 12) {
          Text("mViz").font(.headline)
          Text(model.status).font(.caption)
          if model.library.isPlaying || model.library.isPaused {
            HStack {
              Button(model.library.isPlaying ? "Pause music" : "Resume music") {
                model.library.togglePause(model: model)
              }
              Button("Next track") { model.library.skip(model: model) }
            }
          }
          Text(model.activeMotion.rawValue).font(.subheadline).foregroundStyle(.secondary)
          if showSettings {
            ScrollView {
              VStack {
                VisualizerControls(model: model)
                HStack {
                  Text("Intensity")
                  Slider(
                    value: Binding(get: { model.intensity }, set: { model.intensity = $0 }),
                    in: 0.2...1)
                }
                HStack {
                  Text("Sensitivity")
                  Slider(
                    value: Binding(get: { model.sensitivity }, set: { model.sensitivity = $0 }),
                    in: 0.5...10)
                }
              }
            }.frame(maxHeight: 400)
          }
          VUMeterView(model: model)
          HStack {
            Button(showSettings ? "Hide settings" : "Settings", systemImage: "slider.horizontal.3")
            {
              showSettings.toggle()
            }
            Button(
              model.listening ? "Stop mic" : "Microphone",
              systemImage: model.listening ? "mic.fill" : "mic"
            ) {
              if model.listening {
                model.stopListening()
              } else {
                Task { await model.start() }
              }
            }
            Button("Leave", systemImage: "xmark") {
              Task { await dismissSpace() }
            }
          }
        }
        .frame(width: 540)
        .padding(20)
        .glassBackgroundEffect()
      }
    }
    .onAppear {
      model.isImmersed = true
    }
    .task(id: model.needsRoomGeometry, priority: .low) {
      let activeField = field ?? ParticleField()
      if field == nil { field = activeField }
      await activeField.environment.run(enabled: model.needsRoomGeometry, model: model)
    }
    .onChange(of: reduceMotion, initial: true) { _, value in model.reduceMotion = value }
    .onChange(of: model.recenterStage) { _, _ in field?.recenterStage() }
    .onDisappear {
      updateSubscription = nil
      field?.stopRoom(model: model)
      model.isImmersed = false
      model.stop(preserveMusic: true)
    }
  }
}
