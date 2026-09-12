import Foundation

/// 10-band ISO Graphic Equalizer (GEQ) filter bank with zero latency.
/// Center frequencies: 31.25 Hz, 62.5 Hz, 125 Hz, 250 Hz, 500 Hz, 1 kHz, 2 kHz, 4 kHz, 8 kHz, 16 kHz.
public struct BandAnalyzer: Sendable {
  public static let centerFrequencies: [Float] = [
    31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
  ]

  // Biquad state for each of the 10 bands packed into SIMD16 (zero heap allocations)
  private var x1 = SIMD16<Float>.zero
  private var x2 = SIMD16<Float>.zero
  private var y1 = SIMD16<Float>.zero
  private var y2 = SIMD16<Float>.zero

  // Cached coefficients packed into SIMD16
  private var cachedSampleRate: Double = 0
  private var b0 = SIMD16<Float>.zero
  private var a1 = SIMD16<Float>.zero
  private var a2 = SIMD16<Float>.zero

  public init() {}

  private mutating func updateCoefficients(sampleRate: Double) {
    guard sampleRate != cachedSampleRate else { return }
    cachedSampleRate = sampleRate
    let q: Float = 1.414 // 1 octave bandwidth
    b0 = .zero; a1 = .zero; a2 = .zero
    for i in 0..<10 {
      let fc = Self.centerFrequencies[i]
      if Double(fc) >= sampleRate * 0.48 {
        continue
      }
      let w0 = Float(2.0 * Double.pi * Double(fc) / sampleRate)
      let alpha = sin(w0) / (2.0 * q)
      let a0 = 1.0 + alpha
      b0[i] = (sin(w0) / 2.0) / a0
      a1[i] = (-2.0 * cos(w0)) / a0
      a2[i] = (1.0 - alpha) / a0
    }
  }

  /// Process incoming PCM float samples and return macro bands (bass, mid, treble) for backward compatibility.
  public mutating func process(
    _ samples: UnsafePointer<Float>, count: Int, sampleRate: Double
  ) -> SIMD3<Float> {
    let (macro, _) = processDetailed(samples, count: count, sampleRate: sampleRate)
    return macro
  }

  /// Process incoming PCM float samples and return both 3-band macro and 10-band ISO GEQ energy.
  public mutating func processDetailed(
    _ samples: UnsafePointer<Float>, count: Int, sampleRate: Double
  ) -> (macro: SIMD3<Float>, geq10: SIMD16<Float>) {
    guard count > 0, sampleRate > 0 else { return (.zero, .zero) }
    updateCoefficients(sampleRate: sampleRate)

    var power = SIMD16<Float>.zero

    for s in 0..<count {
      let sample = samples[s]
      let x = sample.isFinite ? sample : 0
      let xVec = SIMD16<Float>(repeating: x)
      // Vectorized biquad bandpass filter across all 10 bands simultaneously:
      // y[n] = b0 * (x[n] - x[n-2]) - a1 * y[n-1] - a2 * y[n-2]
      let y = b0 * (xVec - x2) - a1 * y1 - a2 * y2
      x2 = x1
      x1 = xVec
      y2 = y1
      y1 = y
      power += y * y
    }

    let invCount = 1.0 / Float(count)
    var geq10 = SIMD16<Float>.zero
    for i in 0..<10 {
      geq10[i] = sqrt(power[i] * invCount)
    }

    // Macro bands:
    // Bass = (31.25Hz, 62.5Hz, 125Hz)
    let bass = sqrt((power[0] + power[1] + power[2]) * invCount)
    // Mid = (250Hz, 500Hz, 1kHz, 2kHz)
    let mid = sqrt((power[3] + power[4] + power[5] + power[6]) * invCount)
    // High = (4kHz, 8kHz, 16kHz)
    let high = sqrt((power[7] + power[8] + power[9]) * invCount)

    return (SIMD3<Float>(bass, mid, high), geq10)
  }
}
