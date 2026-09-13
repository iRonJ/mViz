import SwiftUI

/// Shared settings stay synchronized between the window and immersive panel.
struct VisualizerControls: View {
  @Bindable var model: VisualizerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle("Show surroundings", isOn: $model.passthrough)
      Toggle("Logarithmic audio response", isOn: $model.logarithmicLevels)
      Text("Lifts quieter musical details. Turn off to compare with linear response.")
        .font(.caption).foregroundStyle(.secondary)
      Toggle("Transient rate-of-change dynamics", isOn: $model.transientDynamics)
      Text("Drives particle bursts and sizzle from frequency changes rather than sustained volume.")
        .font(.caption).foregroundStyle(.secondary)
      Picker(
        "Movement",
        selection: Binding(
          get: { model.motion },
          set: {
            model.motion = $0
            model.automaticModes = false
            if $0 == .room { model.roomEnabled = true }
          }
        )
      ) {
        ForEach(MotionMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
      }
      Toggle("Journey • change movement automatically", isOn: $model.automaticModes)
      if model.automaticModes {
        Text("Now playing: \(model.activeMotion.rawValue)").font(.caption).foregroundStyle(
          .secondary)
      }
      Toggle("Include Room bounce", isOn: $model.roomEnabled)
      if model.needsRoomGeometry {
        Text(model.roomStatus).font(.caption).foregroundStyle(.secondary)
      }
      Picker("Emitter shape", selection: $model.shape) {
        ForEach(EmitterForm.allCases) { shape in Text(shape.rawValue).tag(shape) }
      }
      Picker("Particle style", selection: $model.particleStyle) {
        ForEach(ParticleStyle.allCases) { style in Text(style.rawValue).tag(style) }
      }
      HStack {
        Text("Particle size \(Int((model.particleSize * 100).rounded()))%").monospacedDigit()
        Slider(value: $model.particleSize, in: 0.25...2, step: 0.05)
          .accessibilityLabel("Particle size")
      }
      if model.activeMotion == .line || model.activeMotion == .grid || model.motion == .line
        || model.motion == .grid || model.activeMotion == .flurry || model.motion == .flurry
      {
        Button("Center stage in front of me", systemImage: "scope") { model.recenterStage += 1 }
      }
      Picker("Beat lighting", selection: $model.beatLighting) {
        ForEach(BeatLightingStyle.allCases) { style in Text(style.rawValue).tag(style) }
      }
      if model.beatLighting == .evolving {
        Text(
          "Transitions with movement • current mode: \(model.activeMotion.definition.lightingStyle.rawValue)"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if model.beatLighting != .off {
        HStack {
          Text("Light intensity")
          Slider(value: $model.lightingIntensity, in: 0.03...0.3)
        }
        Text("Strobe is limited to two flashes per second. Reduce Motion uses a soft pulse.")
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Text("Motion speed \(model.motionSpeed, specifier: "%.2f")×").monospacedDigit()
        Slider(value: $model.motionSpeed, in: 0.25...3)
      }
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("Audio sync delay \(model.audioDelay, specifier: "%.2f")s").monospacedDigit()
          Slider(value: $model.audioDelay, in: 0...0.6, step: 0.01)
        }
        Text(
          "Compensates for graphics pipeline latency so visual beats land precisely on the beat."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
