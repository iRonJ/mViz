import Foundation
#if canImport(UIKit)
  import UIKit
#endif

struct VolcanoMode: MotionPattern {
  var lightingStyle: BeatLightingStyle { .strobe }
  func angularVelocity(time: Float) -> Float { 0.1 * sin(time * 0.4) }

  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    let u: Float = abs(sin(phase * 1.5))
    let r: Float = 2.6 * sqrt(u) * (0.85 + 0.15 * cos(time * 0.4 + phase))
    let y: Float = 0.18 + 0.08 * sin(time * 0.5 + phase)
    return [r, y, 0]
  }
  func dynamics(bass: Float) -> ModeDynamics {
    let b = min(1, max(0, bass))
    return ModeDynamics(
      direction: [0, 1, 0],
      speedBoost: 0.18 + b * 3.82,
      gravity: -0.7 - b * 1.5,
      spreadBoost: 0.06 + b * 0.38,
      birthBoost: b,
      lifeSpan: 3.5,
      stretch: 0.8 + b * 1.8,
      sizeScale: 1,
      form: .cone
    )
  }

  #if canImport(UIKit)
    func customEmitterColor(
      index: Int,
      envelope: SIMD3<Float>,
      trebleSizzle: Float,
      paletteHue: Float,
      beatIntensity: Float,
      activity: Float
    ) -> (start: UIColor, end: UIColor)? {
      let magmaHue = CGFloat(
        (0.02 + envelope.x * 0.10 + trebleSizzle * 0.05 + paletteHue * 0.15)
          .truncatingRemainder(dividingBy: 1.0))
      let magmaBrightness = CGFloat(min(1.0, 0.18 + activity * 0.47 + beatIntensity * 0.35))
      let magmaStart = UIColor(
        hue: magmaHue >= 0 ? magmaHue : magmaHue + 1.0,
        saturation: CGFloat(max(0.2, 0.85 - trebleSizzle * 0.55)),
        brightness: magmaBrightness,
        alpha: 1.0
      )
      return (start: magmaStart, end: .red.withAlphaComponent(0))
    }
  #endif
}
