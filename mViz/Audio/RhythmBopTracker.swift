import Foundation

/// Vectorized fast/slow dual-window envelope tracker that detects musical "bop"
/// (rhythmic drum hits, bass drops, and melodic/percussive transients)
/// even during loud, sustained, or wall-of-sound musical passages.
/// Works with any SIMD float vector (e.g. SIMD3<Float> for [Bass, Mid, High] registers).
public struct RhythmBopTracker<V: SIMD & Sendable>: Sendable where V.Scalar == Float {
  /// Instantaneous fast envelope (attacks in ~12ms, decays in ~50ms)
  public private(set) var fast = V()
  /// Slower running baseline envelope (tracks sustained loudness over ~300ms)
  public private(set) var slow = V()
  /// Normalized rhythmic transient pulse [0...1] with instant attack and musical decay (~180ms)
  public private(set) var bop = V()
  private var previous = V()

  public init() {}

  public mutating func update(
    signal: V,
    dt: Float,
    fastAttackRates: V = V(repeating: 85),
    fastDecayRates: V = V(repeating: 22),
    slowAttackRates: V = V(repeating: 4.5),
    slowDecayRates: V = V(repeating: 2.5)
  ) {
    let dtClamped = max(0.005, dt)
    let count = signal.scalarCount
    for i in 0..<count {
      let s = max(0, signal[i])

      // Fast tracking (instantaneous attack for drums and transients)
      let fRate = s > fast[i] ? fastAttackRates[i] : fastDecayRates[i]
      fast[i] += (s - fast[i]) * (1 - exp(-dtClamped * fRate))

      // Slow tracking (tracks steady-state loudness without suffocating continuous rhythm)
      let sRate = s > slow[i] ? slowAttackRates[i] : slowDecayRates[i]
      slow[i] += (s - slow[i]) * (1 - exp(-dtClamped * sRate))

      // Instantaneous onset (frame-to-frame positive step for zero-latency transient response)
      let onset = max(0, s - previous[i])
      let onsetBoost = min(1.0, (onset / dtClamped) * 0.15)

      // Crest above running baseline with adaptive headroom
      let rawDelta = max(0, fast[i] - slow[i])
      let delta = max(0, rawDelta - 0.04)
      let headroom = max(0.12, 1.0 - slow[i] * 0.45)
      let contrast = min(1.0, (delta / headroom) * 2.8)

      // Combined bop responds immediately to attacks and tracks rhythmic pulse continuously
      let targetBop = min(1.0, max(onsetBoost, pow(contrast, 0.9)))
      if targetBop > bop[i] {
        bop[i] = targetBop
      } else {
        bop[i] += (targetBop - bop[i]) * (1 - exp(-dtClamped * 18))
      }
      previous[i] = s
    }
  }
}
