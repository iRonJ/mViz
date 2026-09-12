import Foundation

/// 10-band ISO Graphic Equalizer (GEQ) filter bank with zero latency.
/// Center frequencies: 31.25 Hz, 62.5 Hz, 125 Hz, 250 Hz, 500 Hz, 1 kHz, 2 kHz, 4 kHz, 8 kHz, 16 kHz.
public struct BandAnalyzer: Sendable {
  public static let centerFrequencies: [Float] = [
    31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
  ]

  // Biquad state for each of the 10 bands
  private var x1 = [Float](repeating: 0, count: 10)
  private var x2 = [Float](repeating: 0, count: 10)
  private var y1 = [Float](repeating: 0, count: 10)
  private var y2 = [Float](repeating: 0, count: 10)

  // Cached coefficients
  private var cachedSampleRate: Double = 0
  private var b0 = [Float](repeating: 0, count: 10)
  private var a1 = [Float](repeating: 0, count: 10)
  private var a2 = [Float](repeating: 0, count: 10)

  public init() {}

  private mutating func updateCoefficients(sampleRate: Double) {
    guard sampleRate != cachedSampleRate else { return }
    cachedSampleRate = sampleRate
    let q: Float = 1.414 // 1 octave bandwidth
    for i in 0..<10 {
      let fc = Self.centerFrequencies[i]
      if Double(fc) >= sampleRate * 0.48 {
        b0[i] = 0; a1[i] = 0; a2[i] = 0
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

    var power = [Float](repeating: 0, count: 10)

    for s in 0..<count {
      let x = samples[s].isFinite ? samples[s] : 0
      for i in 0..<10 {
        guard b0[i] != 0 else { continue }
        // Biquad bandpass filter: y[n] = b0*(x[n] - x[n-2]) - a1*y[n-1] - a2*y[n-2]
        let y = b0[i] * (x - x2[i]) - a1[i] * y1[i] - a2[i] * y2[i]
        x2[i] = x1[i]
        x1[i] = x
        y2[i] = y1[i]
        y1[i] = y
        power[i] += y * y
      }
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
