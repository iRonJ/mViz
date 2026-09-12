import Foundation

enum BeatLightingStyle: String, CaseIterable, Identifiable {
  case evolving = "Evolving"
  case off = "Off"
  case pulse = "Pulse"
  case strobe = "Strobe"
  var id: Self { self }
}

/// Detect bass onsets, with a refractory period that caps flashes at 2 Hz.
struct BeatPulse {
  private var previous: Float = 0
  private var baseline: Float = 0
  private var cooldown: Float = 1
  private var age: Float = 10
  private var strength: Float = 0
  private(set) var beatTriggered: Bool = false
  private(set) var paletteHue: Float = 0
  private var targetPaletteHue: Float = 0

  mutating func update(bass: Float, dt: Float, style: BeatLightingStyle) -> Float {
    switch style {
    case .off:
      return update(bass: bass, dt: dt, pulseWeight: 0, strobeWeight: 0)
    case .pulse:
      return update(bass: bass, dt: dt, pulseWeight: 1, strobeWeight: 0)
    case .strobe:
      return update(bass: bass, dt: dt, pulseWeight: 0, strobeWeight: 1)
    case .evolving:
      return update(bass: bass, dt: dt, pulseWeight: 1, strobeWeight: 0)
    }
  }

  mutating func update(bass: Float, dt: Float, pulseWeight: Float, strobeWeight: Float) -> Float {
    let dt = max(0, dt)
    cooldown += dt
    age += dt
    baseline += (bass - baseline) * (1 - exp(-dt * 1.5))
    beatTriggered = false

    // Beat onset detection (independent of lighting style, capped at 2 Hz for photosafety)
    if cooldown >= 0.5 && bass > 0.08 && bass - previous > 0.015
      && bass > baseline * 1.10
    {
      age = 0
      cooldown = 0
      strength = min(1, bass * 1.5)
      beatTriggered = true

      // Advance palette target by golden ratio fraction (~0.618034)
      // which rotates to aesthetically pleasing, highly distinct harmonic hues.
      targetPaletteHue += 0.618034
    }
    previous = bass

    // Continuous smooth interpolation towards target hue, plus a subtle ambient drift
    targetPaletteHue += dt * 0.015
    let smoothing = 1 - exp(-dt * 5.0)
    paletteHue += (targetPaletteHue - paletteHue) * smoothing
    if paletteHue >= 100.0 {
      paletteHue = paletteHue.truncatingRemainder(dividingBy: 1.0)
      targetPaletteHue = targetPaletteHue.truncatingRemainder(dividingBy: 1.0)
    }

    let active = pulseWeight > 0.001 || strobeWeight > 0.001
    guard active else {
      strength = 0
      return 0
    }
    let pulseVal = strength * exp(-age * 5)
    let strobeVal = age < 0.07 ? strength : 0
    return pulseWeight * pulseVal + strobeWeight * strobeVal
  }
}
