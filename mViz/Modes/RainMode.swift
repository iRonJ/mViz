import Foundation

struct RainMode: MotionPattern {
  func angularVelocity(time: Float) -> Float { -0.07 + 0.1 * sin(time * 0.35) }

  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    let u: Float = abs(sin(phase * 1.5))
    let r: Float = 2.7 * sqrt(u) * (0.85 + 0.15 * sin(time * 0.3 + phase))
    let y: Float = 3.65 + 0.1 * cos(time * 0.4 + phase)
    return [r, y, 0]
  }
  func dynamics(bass: Float) -> ModeDynamics {
    let b = min(1, max(0, bass))
    return ModeDynamics(
      direction: [0, -1, 0],
      speedBoost: 0.15 + b * 2.35,
      gravity: -0.25 - b * 0.95,
      spreadBoost: b * 0.12,
      birthBoost: b * 0.9,
      lifeSpan: 3.5,
      stretch: 2.0 + b * 5.0,
      sizeScale: 0.55 + b * 0.35,
      form: .plane
    )
  }
}
