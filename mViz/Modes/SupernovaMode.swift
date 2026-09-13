import Foundation

/// Relativistic pulsar and cosmic singularity featuring polar plasma jets and spiraling accretion disk.
struct SupernovaMode: MotionPattern {
  var lightingStyle: BeatLightingStyle { .strobe }
  func angularVelocity(time: Float) -> Float { 0.42 + 0.08 * sin(time * 0.3) }

  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    let polarWeight = pow(abs(sin(phase * 2)), 3.0)
    let isZenith = sin(phase) >= 0

    // Accretion disk pose
    let diskR: Float = 2.65 + 0.45 * cos(phase * 3 + time * 0.5)
    let diskY: Float = 1.6 + 0.45 * sin(phase * 2 + time * 0.4)
    let diskTheta: Float = 0.25 * sin(time * 0.4 + phase)

    // Polar jet pose
    let jetY: Float = isZenith ? 3.45 + 0.15 * sin(time * 1.5 + phase) : 0.32 + 0.12 * sin(time * 1.5 + phase)
    let jetR: Float = 0.22 + 0.08 * cos(time * 1.2 + phase)

    let r = (1 - polarWeight) * diskR + polarWeight * jetR
    let y = (1 - polarWeight) * diskY + polarWeight * jetY
    let theta = diskTheta

    return [r, y, theta]
  }

  func dynamics(bass: Float) -> ModeDynamics {
    let b = min(1, max(0, bass))
    return ModeDynamics(
      direction: nil,
      speedBoost: 0.06 + b * 1.24, // relativistic blast on bass drops
      gravity: 0,
      spreadBoost: 0.08 + b * 0.38,
      birthBoost: b * 0.9,
      lifeSpan: 2.2,
      stretch: 1.4 + b * 2.8, // relativistic streak distortion
      sizeScale: 0.95 + b * 0.6,
      form: .cone
    )
  }
}
