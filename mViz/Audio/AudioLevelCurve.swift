import Foundation

/// Maps sensitivity-adjusted amplitude into visual intensity, not decibels.
enum AudioLevelCurve {
  static func map(_ amplitude: Float, logarithmic: Bool) -> Float {
    guard amplitude.isFinite else { return 0 }
    let level = min(1, max(0, amplitude))
    guard logarithmic else { return level }
    // A small floor avoids lifting near-silence; both endpoints remain exact.
    let audible = max(0, (level - 0.002) / 0.998)
    return log1p(9 * audible) / log(10)
  }
}
