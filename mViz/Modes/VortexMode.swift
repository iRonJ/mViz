import Foundation

struct VortexMode: MotionPattern {
  var lightingStyle: BeatLightingStyle { .strobe }
  func angularVelocity(time: Float) -> Float { 0.55 * cos(time * 0.18) }

  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    let u: Float = cos(phase + time * 0.6)
    let y: Float = 1.8 + 1.6 * u
    let r: Float = 0.2 + 2.5 * sqrt(max(0, 1 - u * u)) * (0.85 + 0.15 * sin(phase + time * 0.3))
    return [r, y, 0.8 * sin(time * 0.3) + 0.5 * u]
  }

  func dynamics(bass: Float) -> ModeDynamics {
    let b = min(1, max(0, bass))
    return ModeDynamics(
      speedBoost: 0.08 + b * 1.15,
      spreadBoost: 0.04 + b * 0.36,
      birthBoost: b * 0.85,
      stretch: 1.1 + b * 2.4
    )
  }
}
