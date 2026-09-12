import Foundation

/// Blend cylindrical coordinates so transitions never cut across the viewer.
/// Both automatic and manual changes use the same continuous blend.
struct MotionBlend {
  private(set) var weights: [Float] = MotionMode.allCases.map { $0 == .orbit ? 1 : 0 }
  subscript(_ mode: MotionMode) -> Float { weights[mode.index] }

  private var orbitAngle: Float = 0
  private var motionTime: Float = 0

  mutating func advance(toward mode: MotionMode, dt: Float, speed: Float = 1) {
    let amount = 1 - exp(-max(0, dt) * 0.8)
    let targetIndex = mode.index
    for index in weights.indices {
      let target: Float = index == targetIndex ? 1 : 0
      weights[index] += (target - weights[index]) * amount
    }
    let motionStep = MotionRate(speed).advance(max(0, dt))
    motionTime += motionStep
    var velocity: Float = 0
    let allModes = MotionMode.allCases
    for index in weights.indices {
      let w = weights[index]
      if w > 0.001 {
        velocity += allModes[index].definition.angularVelocity(time: motionTime) * w
      }
    }
    orbitAngle += velocity * motionStep
  }

  func position(phase: Float, time: Float, bass: Float) -> SIMD3<Float> {
    // x = radius, y = height, z = angular offset relative to the shared orbit.
    var pose = SIMD3<Float>.zero
    let allModes = MotionMode.allCases
    for index in weights.indices {
      let w = weights[index]
      if w > 0.001 {
        pose += allModes[index].definition.pose(phase: phase, time: time) * w
      }
    }
    let angle = phase + orbitAngle + pose.z
    let rawRadius = max(0, pose.x + bass * 0.3 * min(1, pose.x))
    // Maintain a safe viewing sphere around the user at eye level (1.5m),
    // while allowing emitters to pass directly overhead and underfoot.
    let dy = abs(pose.y - 1.5)
    let clearance: Float = 1.35
    let minRadius: Float = dy < clearance ? sqrt(max(0, clearance * clearance - dy * dy)) : 0
    let radius = max(rawRadius, minRadius)
    let safeRadius = radius.isFinite && !radius.isNaN ? radius : 2.5
    let safeY = pose.y.isFinite && !pose.y.isNaN ? pose.y : 1.5
    return [cos(angle) * safeRadius, safeY, sin(angle) * safeRadius]
  }
}
