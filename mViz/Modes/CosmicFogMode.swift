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
    ModeDynamics(
      direction: nil,
      speedBoost: -0.04, // slow atmospheric drifting mist
      gravity: 0,
      spreadBoost: 0.75, // wide diffuse volumetric mist
      birthBoost: 60 * bass, // volumetric cloud breathes with the music
      lifeSpan: 3.8, // long-lived drifting fog
      stretch: nil,
      sizeScale: 2.2, // large soft volumetric particle cloud
      form: .plane
    )
  }
}
