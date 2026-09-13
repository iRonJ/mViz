import Foundation

struct MirrorLineMode: MotionPattern, StagePositionable {
  var lightingStyle: BeatLightingStyle { .strobe }
  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    [2.8, 1.5, 0]
  }
  func stagePosition(index: Int, time: Float, bass: Float) -> SIMD3<Float> {
    let x = (Float(index) - 5.5) * 0.24
    let row: Float = 1.4
    let wave = sin(abs(x) * 2.2 + time * 1.2) * (0.08 + bass * 0.18)
    return [x, row + wave, -2.5]
  }

  func dynamics(bass: Float) -> ModeDynamics {
    let b = min(1, max(0, bass))
    return ModeDynamics(
      direction: [0, 1, 0],
      speedBoost: 0.05 + b * 1.05,
      spreadBoost: b * 0.18,
      birthBoost: b * 0.8
    )
  }
}
