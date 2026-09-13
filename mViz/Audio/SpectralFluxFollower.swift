import Foundation

/// Vectorized envelope smoothing, running baseline follower, and spectral flux tracker.
/// Works with any SIMD float vector (e.g. SIMD3<Float> for macro bands, SIMD16<Float> for 10-band GEQ).
public struct SpectralFluxFollower<V: SIMD & Sendable>: Sendable where V.Scalar == Float {
  public private(set) var envelope = V()
  public private(set) var baseline = V()
  public private(set) var flux = V()
  private var previous = V()

  public init() {}

  public mutating func update(
    signal: V,
    dt: Float,
    attackRates: V,
    decayRates: V,
    fluxAttackRate: Float = 65,
    fluxDecayRate: Float = 16
  ) {
    let dtClamped = max(0.005, dt)
    let count = signal.scalarCount
    for i in 0..<count {
      let s = signal[i]

      // 1. Envelope smoothing
      let envRate = s > envelope[i] ? attackRates[i] : decayRates[i]
      envelope[i] += (s - envelope[i]) * (1 - exp(-dt * envRate))

      // 2. Adaptive running baseline follower (slowly tracks steady-state loudness)
      let baseRate: Float = s > baseline[i] ? 2.5 : 1.8
      baseline[i] += (s - baseline[i]) * (1 - exp(-dt * baseRate))

      // 3. Instantaneous positive derivative & adaptive contrast (Weber-Fechner Law)
      let delta = max(0, s - previous[i])
      let instant = min(1.0, (delta / dtClamped) * 0.22)
      let contrast = max(0, s - baseline[i]) / max(0.2, 1.0 - baseline[i] * 0.5)
      let targetFlux = min(1.0, max(instant, contrast * 0.9))

      // 4. Flux envelope
      let fRate = targetFlux > flux[i] ? fluxAttackRate : fluxDecayRate
      flux[i] += (targetFlux - flux[i]) * (1 - exp(-dt * fRate))
    }
    previous = signal
  }
}
