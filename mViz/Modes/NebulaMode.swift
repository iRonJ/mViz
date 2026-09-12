import Foundation

struct NebulaMode: MotionPattern {
  func angularVelocity(time: Float) -> Float { 0.24 * cos(time * 0.22) }

  func pose(phase: Float, time: Float) -> SIMD3<Float> {
    let R: Float = 2.6 + 0.3 * cos(time * 0.3 + phase)
    let theta: Float = phase * 2 + time * 0.4
    let alpha: Float = sin(phase * 3) * (Float.pi / 2 * 0.95)
    let y: Float = 1.8 + 1.55 * sin(theta) * sin(alpha)
    let r: Float = R * sqrt(cos(theta) * cos(theta) + sin(theta) * sin(theta) * cos(alpha) * cos(alpha))
    return [r, y, 0]
  }
}
