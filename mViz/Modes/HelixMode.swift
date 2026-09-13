import Foundation

struct HelixMode: MotionPattern {
  var lightingStyle: BeatLightingStyle { .pulse }
  func angularVelocity(time: Float) -> Float { -0.25 }

  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    let u: Float = sin(phase * 2 + time * 0.5)
    let y: Float = 1.8 + 1.6 * u
    let r: Float = 0.15 + 2.45 * sqrt(max(0, 1 - u * u))
    return [r, y, 0.5 * u]
  }

  func dynamics(bass: Float) -> ModeDynamics {
    let b = min(1, max(0, bass))
    return ModeDynamics(
      speedBoost: 0.05 + b * 0.95,
      spreadBoost: 0.02 + b * 0.28,
      birthBoost: b * 0.8,
      stretch: 1.0 + b * 2.2
    )
  }
}
