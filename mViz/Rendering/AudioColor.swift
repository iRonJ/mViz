import Foundation

#if canImport(UIKit)
  import UIKit
#endif

/// Spectral balance sets hue; bass warms it, treble brightens/desaturates it.
func reactiveColor(bands: SIMD3<Float>, offset: Float) -> SIMD3<Float> {
  let total = max(0.001, bands.x + bands.y + bands.z)
  let hue = (0.02 + (bands.y * 0.38 + bands.z * 0.68) / total + offset).truncatingRemainder(
    dividingBy: 1)
  return [
    hue, max(0.25, 0.85 - bands.z * 0.5), min(1, 0.35 + max(bands.x, max(bands.y, bands.z)) * 0.65),
  ]
}

#if canImport(UIKit)
  /// Computes particle start and end colors incorporating base hue, beat palette offset, high-frequency sizzle, and beat brightness pulse.
  func reactiveEmitterColors(
    baseHue: Float,
    bands: SIMD3<Float>,
    highFrequency: Float,
    hueOffset: Float = 0,
    beatPulse: Float = 0
  ) -> (start: UIColor, end: UIColor) {
    let clampedHigh = min(1, max(0, highFrequency))
    let sizzle = pow(clampedHigh, 1.25)
    let beat = min(1.0, max(0, beatPulse))

    // Overall hue combining base emitter hue, beat palette offset, and spectral balance
    var rawHue = (baseHue + hueOffset).truncatingRemainder(dividingBy: 1.0)
    if rawHue < 0 { rawHue += 1.0 }
    let hue = CGFloat(rawHue)

    // High-frequency sizzle desaturates towards brilliant incandescent sparkle (white-hot/electric core)
    let startSaturation = CGFloat(max(0.16, 0.82 - sizzle * 0.55 + bands.x * 0.10 - beat * 0.10))

    // Particle brightness dynamically pulses with the beat!
    // Baseline at rest: ~0.60. On beat pulse: surges up to 1.0.
    let startBrightness = CGFloat(min(1.0, 0.60 + beat * 0.40 + sizzle * 0.18 + bands.x * 0.08))

    let start = UIColor(
      hue: hue, saturation: startSaturation, brightness: startBrightness, alpha: 1.0)

    // Trailing end color: shifts slightly along the spectrum and fades to zero alpha,
    // with its trailing brightness also breathing with the beat.
    var rawEndHue = (Float(hue) + 0.14 + sizzle * 0.08).truncatingRemainder(dividingBy: 1.0)
    if rawEndHue < 0 { rawEndHue += 1.0 }
    let endBrightness = CGFloat(min(0.85, 0.40 + beat * 0.35 + sizzle * 0.15))
    let end = UIColor(hue: CGFloat(rawEndHue), saturation: 0.9, brightness: endBrightness, alpha: 0.0)

    return (start, end)
  }

#endif
