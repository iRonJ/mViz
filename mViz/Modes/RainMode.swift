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
    ModeDynamics(
      direction: [0, -1, 0], speedBoost: 1.1, gravity: -0.5,
      spreadBoost: 0, birthBoost: 0, lifeSpan: 3.5, stretch: 5, sizeScale: 0.65, form: .plane)
  }
}
