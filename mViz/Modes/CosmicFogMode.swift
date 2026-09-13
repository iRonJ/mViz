import Foundation

/// Volumetric 3D particle mist cloud that fills the room, slowly breathing with harmonic laminar flow.
struct CosmicFogMode: MotionPattern {
  var lightingStyle: BeatLightingStyle { .pulse }
  func angularVelocity(time: Float) -> Float { 0.06 * cos(time * 0.15) }

  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    let u = sin(phase * 3 + time * 0.12)
    let v = cos(phase * 2 + time * 0.08)
    let r: Float = 2.35 + 0.65 * v
    let y: Float = 1.75 + 1.15 * u
    let theta: Float = 0.2 * sin(time * 0.15 + phase)
    return [r, y, theta]
  }

  func dynamics(bass: Float) -> ModeDynamics {
    let b = min(1, max(0, bass))
    return ModeDynamics(
      direction: nil,
      speedBoost: -0.05 + b * 0.28,
      gravity: 0,
      spreadBoost: 0.55 + b * 0.45,
      birthBoost: b * 0.85,
      lifeSpan: 3.8,
      stretch: nil,
      sizeScale: 1.7 + b * 1.0,
      form: .plane
    )
  }
}
