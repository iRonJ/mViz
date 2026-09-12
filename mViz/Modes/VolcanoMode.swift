import Foundation

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
    ModeDynamics(
      direction: [0, 1, 0], speedBoost: 1.5 + bass * 3, gravity: -1.8,
      spreadBoost: 0.3, birthBoost: bass, lifeSpan: 3.5, stretch: nil, sizeScale: 1, form: .cone)
  }
}
