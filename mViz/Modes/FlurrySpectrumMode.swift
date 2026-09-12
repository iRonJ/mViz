import Foundation

/// A stationary distant equalizer with flowing, Flurry-inspired light trails.
struct FlurrySpectrumMode: MotionPattern {
  static let bandCount = 10
  static let baseline: Float = -0.9

  func pose(phase: Float, time: Float) -> SIMD3<Float> { [3, 1.5, 0] }

  func barHeight(level: Float) -> Float {
    let value = level.isFinite ? min(1, max(0, level)) : 0
    return 0.025 + value * 2.2
  }

  func basePosition(band: Int) -> SIMD3<Float> {
    [(Float(band) - 4.5) * 0.56, Self.baseline, -5]
  }
}
