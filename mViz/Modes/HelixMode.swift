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
}
