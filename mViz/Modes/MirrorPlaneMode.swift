import Foundation

struct MirrorPlaneMode: MotionPattern {
  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    [2.8, 1.5, 0]
  }
  func stagePosition(index: Int, time: Float, bass: Float) -> SIMD3<Float> {
    let x = (Float(index % 4) - 1.5) * 0.65
    let row = Float(index / 4 - 1) * 0.5
    let wave = sin(abs(x) * 2.2 + time * 1.2) * (0.08 + bass * 0.18)
    return [x, row + wave, -2.5]
  }
}
