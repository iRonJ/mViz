import SwiftUI

/// 10-band Graphic Equalizer & 3-band VU meter tapped into the audio DSP engine.
struct VUMeterView: View {
  var model: VisualizerModel

  static let bandLabels = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

  private var isAudioActive: Bool {
    model.listening || model.library.isPlaying || model.isImmersed
  }

  var body: some View {
    if isAudioActive {
      TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
        let _ = context.date
        meterCard(macro: currentMacroLevels, geq10: current10BandLevels)
      }
    } else {
      meterCard(macro: .zero, geq10: .zero)
    }
  }

  private var currentMacroLevels: SIMD3<Float> {
    if model.isImmersed {
      return model.geqLevels
    }
    let raw = model.bands * model.sensitivity * 8
    return SIMD3<Float>(
      min(1, max(0, raw.x)),
      min(1, max(0, raw.y)),
      min(1, max(0, raw.z))
    )
  }

  private var current10BandLevels: SIMD16<Float> {
    if model.isImmersed {
      return model.geq10Levels
    }
    let raw10 = model.bands10 * model.sensitivity * 8
    var res = SIMD16<Float>.zero
    for i in 0..<10 {
      res[i] = min(1, max(0, raw10[i]))
    }
    return res
  }

  @ViewBuilder
  private func meterCard(macro: SIMD3<Float>, geq10: SIMD16<Float>) -> some View {
    let hasSignal = macro.x > 0.02 || macro.y > 0.02 || macro.z > 0.02

    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("10-Band Graphic Equalizer & VU", systemImage: "waveform")
          .font(.subheadline.bold())
        Spacer()
        HStack(spacing: 5) {
          Circle()
            .fill(hasSignal ? Color.green : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
            .shadow(color: hasSignal ? .green.opacity(0.8) : .clear, radius: 4)
          Text(hasSignal ? "SIGNAL ACTIVE" : "IDLE")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(hasSignal ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
      }

      // 10-Band Spectrum Equalizer Bars
      HStack(alignment: .bottom, spacing: 6) {
        ForEach(0..<10, id: \.self) { band in
          let level = max(0, min(1, geq10[band]))
          VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
              RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.08))
                .frame(maxWidth: .infinity)
                .frame(height: 38)

              RoundedRectangle(cornerRadius: 3)
                .fill(bandColor(band))
                .frame(maxWidth: .infinity)
                .frame(height: max(2, CGFloat(level) * 38))
                .animation(.easeOut(duration: 0.08), value: level)
            }
            Text(Self.bandLabels[band])
              .font(.system(size: 8, weight: .semibold, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(.vertical, 2)

      // Macro 3-band VU meters
      VStack(spacing: 5) {
        vuBar(label: "BASS", level: macro.x, color: .cyan)
        vuBar(label: "MID ", level: macro.y, color: .purple)
        vuBar(label: "HIGH", level: macro.z, color: .pink)
      }
    }
    .padding(12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
  }

  private func bandColor(_ index: Int) -> Color {
    let colors: [Color] = [
      .cyan, .teal, .blue, .indigo, .purple, .pink, .orange, .yellow, .green, .mint
    ]
    return colors[index % colors.count]
  }

  @ViewBuilder
  private func vuBar(label: String, level: Float, color: Color) -> some View {
    let clamped = max(0, min(1, level))

    HStack(spacing: 8) {
      Text(label)
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 36, alignment: .leading)

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.primary.opacity(0.09))

        HStack(spacing: 2) {
          ForEach(0..<24, id: \.self) { _ in
            Rectangle()
              .fill(Color.primary.opacity(0.04))
              .frame(maxWidth: .infinity)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))

        RoundedRectangle(cornerRadius: 4)
          .fill(
            LinearGradient(
              stops: [
                .init(color: color.opacity(0.8), location: 0.0),
                .init(color: color, location: 0.65),
                .init(color: .orange, location: 0.88),
                .init(color: .red, location: 1.0),
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .scaleEffect(x: CGFloat(max(0.001, clamped)), y: 1.0, anchor: .leading)
          .animation(.easeOut(duration: 0.08), value: clamped)
      }
      .frame(height: 10)

      Text("\(Int(clamped * 100))%")
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 32, alignment: .trailing)
    }
  }
}
