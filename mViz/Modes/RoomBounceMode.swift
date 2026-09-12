import Foundation

struct RoomBounceMode: MotionPattern {
  var lightingStyle: BeatLightingStyle { .pulse }
  func angularVelocity(time: Float) -> Float { -0.12 }

  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    let u: Float = sin(phase + time * 0.35)
    let y: Float = 1.8 + 1.5 * u
    let r: Float = 0.25 + 2.35 * sqrt(max(0, 1 - u * u))
    return [r, y, 0]
  }
}
