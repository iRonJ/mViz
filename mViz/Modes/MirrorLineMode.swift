import Foundation

struct MirrorLineMode: MotionPattern {
  var lightingStyle: BeatLightingStyle { .strobe }
  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    [2.8, 1.5, 0]
  }
  func stagePosition(index: Int, time: Float, bass: Float) -> SIMD3<Float> {
    let x = (Float(index) - 5.5) * 0.24
    let row: Float = 0
    let wave = sin(abs(x) * 2.2 + time * 1.2) * (0.08 + bass * 0.18)
    return [x, row + wave, -2.5]
  }
}
