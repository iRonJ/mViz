import Foundation

/// Vectorized fast/slow dual-window envelope tracker that detects musical "bop"
/// (rhythmic drum hits, bass drops, and melodic/percussive transients)
/// even during loud, sustained, or wall-of-sound musical passages.
/// Works with any SIMD float vector (e.g. SIMD3<Float> for [Bass, Mid, High] registers).
public struct RhythmBopTracker<V: SIMD & Sendable>: Sendable where V.Scalar == Float {
  /// Instantaneous fast envelope (attacks in ~12ms, decays in ~50ms)
  public private(set) var fast = V()
  /// Slower running baseline envelope (tracks sustained loudness over ~200ms)
  public private(set) var slow = V()
  /// Normalized rhythmic transient pulse [0...1] with instant attack and musical decay (~180ms)
  public private(set) var bop = V()

  public init() {}

  public mutating func update(
    signal: V,
    dt: Float,
    fastAttackRates: V = V(repeating: 85),
    fastDecayRates: V = V(repeating: 22),
    slowAttackRates: V = V(repeating: 7),
    slowDecayRates: V = V(repeating: 3.5)
  ) {
    let dtClamped = max(0.005, dt)
    let count = signal.scalarCount
    for i in 0..<count {
      let s = max(0, signal[i])

      // Fast tracking (instantaneous attack for drums and transients)
      let fRate = s > fast[i] ? fastAttackRates[i] : fastDecayRates[i]
      fast[i] += (s - fast[i]) * (1 - exp(-dtClamped * fRate))

      // Slow tracking (tracks steady-state loudness)
      let sRate = s > slow[i] ? slowAttackRates[i] : slowDecayRates[i]
      slow[i] += (s - slow[i]) * (1 - exp(-dtClamped * sRate))

      // Rhythmic transient delta: isolates beats on top of the sustained floor
      // Small 0.02 deadzone ensures steady-state signals relax completely to zero bop
      let rawDelta = max(0, fast[i] - slow[i])
      let delta = max(0, rawDelta - 0.02)
      let headroom = max(0.12, 1.0 - slow[i] * 0.45)
      let normalized = min(1.0, (delta / headroom) * 2.8)

      // Instantaneous peak attack on hits, smooth exponential decay (~180ms release)
      let targetBop = pow(normalized, 0.9)
      if targetBop > bop[i] {
        bop[i] = targetBop
      } else {
        bop[i] += (targetBop - bop[i]) * (1 - exp(-dtClamped * 18))
      }
    }
  }
}
