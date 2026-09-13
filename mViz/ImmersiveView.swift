import RealityKit
import SwiftUI
import UIKit

struct ImmersiveView: View {
  var model: VisualizerModel
  @Environment(\.dismissImmersiveSpace) private var dismissSpace
  @Environment(\.openWindow) private var openWindow
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showSettings = false
  @State private var controlsVisible = true
  @State private var autohideTask: Task<Void, Never>? = nil
  @State private var field: ParticleField?
  @State private var updateSubscription: EventSubscription?
  @State private var tapTarget = Entity()

  private func resetAutohideTimer() {
    autohideTask?.cancel()
    guard !showSettings else { return }
    autohideTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      guard !Task.isCancelled else { return }
      withAnimation(.easeInOut(duration: 0.4)) {
        controlsVisible = false
      }
    }
  }

  private func updateTapTarget() {
    let active = !controlsVisible
    tapTarget.isEnabled = active
    if active {
      tapTarget.components.set(InputTargetComponent())
      tapTarget.components.set(CollisionComponent(shapes: [.generateSphere(radius: 20)], mode: .trigger))
    } else {
      tapTarget.components.remove(InputTargetComponent.self)
      tapTarget.components.remove(CollisionComponent.self)
    }
  }

  var body: some View {
    RealityView { content, attachments in
      let visualizerField = field ?? ParticleField()
      if field == nil { field = visualizerField }
      content.add(visualizerField.root)
      content.add(visualizerField.stageRoot)

      tapTarget.name = "GestureTapTarget"
      updateTapTarget()
      content.add(tapTarget)

      if let controls = attachments.entity(for: "controls") {
        controls.position = [0, 1.1, -1.5]
        content.add(controls)
      }
      updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
        visualizerField.update(dt: Float(event.deltaTime), model: model)
      }
    } update: { _, _ in
      updateTapTarget()
    } attachments: {
      Attachment(id: "controls") {
        VStack(spacing: 14) {
          Text("mViz").font(.headline)
          Text(model.status).font(.caption).foregroundStyle(.secondary)
          if !model.library.tracks.isEmpty || model.library.appleMusicActive {
            HStack(spacing: 16) {
              if model.library.isPlaying || model.library.isPaused {
                Button(
                  model.library.isPlaying ? "Pause music" : "Resume music",
                  systemImage: model.library.isPlaying ? "pause.fill" : "play.fill"
                ) {
                  resetAutohideTimer()
                  model.library.togglePause(model: model)
                }
                Button("Next track", systemImage: "forward.fill") {
                  resetAutohideTimer()
                  model.library.skip(model: model)
                }
              } else {
                Button("Play music", systemImage: "play.fill") {
                  resetAutohideTimer()
                  model.library.skip(model: model)
                }
              }
            }
          }
          Text(model.activeMotion.rawValue).font(.subheadline).foregroundStyle(.secondary)
          if showSettings {
            ScrollView {
              VStack(spacing: 14) {
                VisualizerControls(model: model)
                HStack {
                  Text("Intensity")
                  Slider(
                    value: Binding(
                      get: { model.intensity },
                      set: {
                        model.intensity = $0
                        resetAutohideTimer()
                      }),
                    in: 0.2...1)
                }
                HStack {
                  Text("Sensitivity")
                  Slider(
                    value: Binding(
                      get: { model.sensitivity },
                      set: {
                        model.sensitivity = $0
                        resetAutohideTimer()
                      }),
                    in: 0.5...10)
                }
                Divider()
                PlaylistView(model: model, player: model.library)
              }
              .padding(.vertical, 4)
            }
            .frame(maxHeight: 380)
          }
          VUMeterView(model: model)
          HStack(spacing: 12) {
            Button(showSettings ? "Hide settings" : "Settings", systemImage: "slider.horizontal.3")
            {
              withAnimation(.easeInOut(duration: 0.25)) {
                showSettings.toggle()
              }
            }
            Button(
              model.listening ? "Stop mic" : "Microphone",
              systemImage: model.listening ? "mic.fill" : "mic"
            ) {
              resetAutohideTimer()
              if model.listening {
                model.stopListening()
              } else {
                Task { await model.start() }
              }
            }
            Button("Hide panel", systemImage: "eye.slash") {
              autohideTask?.cancel()
              withAnimation(.easeInOut(duration: 0.3)) {
                controlsVisible = false
              }
            }
            Button("Leave", systemImage: "xmark") {
              autohideTask?.cancel()
              Task { await dismissSpace() }
            }
          }
        }
        .frame(width: 540)
        .padding(20)
        .glassBackgroundEffect()
        .opacity(controlsVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: controlsVisible)
        .allowsHitTesting(controlsVisible)
      }
    }
    .gesture(
      SpatialTapGesture()
        .targetedToEntity(tapTarget)
        .onEnded { _ in
          withAnimation(.easeInOut(duration: 0.35)) {
            controlsVisible = true
          }
          resetAutohideTimer()
        }
    )
    .onAppear {
      model.isImmersed = true
      updateTapTarget()
      resetAutohideTimer()
    }
    .onChange(of: controlsVisible) { _, visible in
      updateTapTarget()
      if visible {
        resetAutohideTimer()
      } else {
        autohideTask?.cancel()
      }
    }
    .onChange(of: showSettings) { _, open in
      if open {
        autohideTask?.cancel()
      } else {
        resetAutohideTimer()
      }
    }
    .task(id: model.needsRoomGeometry, priority: .low) {
      let activeField = field ?? ParticleField()
      if field == nil { field = activeField }
      await activeField.environment.run(enabled: model.needsRoomGeometry, model: model)
    }
    .onChange(of: reduceMotion, initial: true) { _, value in model.reduceMotion = value }
    .onChange(of: model.recenterStage) { _, _ in field?.recenterStage() }
    .onDisappear {
      autohideTask?.cancel()
      updateSubscription = nil
      field?.stopRoom(model: model)
      model.isImmersed = false
      model.stop(preserveMusic: true)
      openWindow(id: "main")
    }
  }
}
