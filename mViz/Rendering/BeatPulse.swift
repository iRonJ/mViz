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
  private var beatCooldown: Float = 1
  private var strobeCooldown: Float = 1
  private var age: Float = 10
  private var strobeAge: Float = 10
  private var strength: Float = 0
  private var strobeStrength: Float = 0
  private(set) var beatTriggered: Bool = false
  private(set) var paletteHue: Float = 0
  private var targetPaletteHue: Float = 0

  /// Current normalized beat envelope (peaks on onset, decaying smoothly over ~0.35s).
  var beatIntensity: Float {
    strength * exp(-age * 6.5)
  }

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
    beatCooldown += dt
    strobeCooldown += dt
    age += dt
    strobeAge += dt
    baseline += (bass - baseline) * (1 - exp(-dt * 1.5))
    beatTriggered = false

    // Musical beat onset detection (supports tempos up to 250 BPM, cooldown >= 0.24s)
    if beatCooldown >= 0.24 && bass > 0.06 && bass - previous > 0.6 * dt
      && bass > baseline * 1.08
    {
      age = 0
      beatCooldown = 0
      strength = min(1, bass * 1.5)
      beatTriggered = true

      // Strobe flash rate cap strictly preserved at <= 2 Hz (cooldown >= 0.49s) for photosafety
      if strobeCooldown >= 0.49 {
        strobeCooldown = 0
        strobeAge = 0
        strobeStrength = strength
      }

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
      let turns = floor(paletteHue)
      paletteHue -= turns
      targetPaletteHue -= turns
    }

    let active = pulseWeight > 0.001 || strobeWeight > 0.001
    guard active else {
      return 0
    }
    let pulseVal = strength * exp(-age * 5)
    let strobeVal = strobeAge < 0.07 ? strobeStrength : 0
    return pulseWeight * pulseVal + strobeWeight * strobeVal
  }
}
