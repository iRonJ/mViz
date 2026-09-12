import Foundation

struct AuroraMode: MotionPattern {
  var lightingStyle: BeatLightingStyle { .pulse }
  func angularVelocity(time: Float) -> Float { 0.12 * sin(time * 0.3) }

  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    let u: Float = 0.5 + 0.5 * sin(phase * 2 + time * 0.25)
    let r: Float = 0.2 + 2.9 * u
    let y: Float = 3.55 - 1.3 * u + 0.25 * sin(phase * 3 + time * 0.6)
    return [r, y, 0.2 * sin(time * 0.4 + phase)]
  }
}
