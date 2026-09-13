import Foundation

import Foundation
for rate in [44100.0, 48000.0] {
    for (frequency, expected) in [(60.0, 0), (1000.0, 1), (10000.0, 2)] {
        var analyzer = BandAnalyzer()
        let samples = (0..<48000).map { Float(sin(2 * Double.pi * frequency * Double($0) / rate)) * 0.5 }
        let bands = samples.withUnsafeBufferPointer { analyzer.process($0.baseAddress!, count: $0.count, sampleRate: rate) }
        for other in 0..<3 where other != expected { precondition(bands[expected] > bands[other], "Wrong dominant band: \(bands)") }
    }
}
var analyzer = BandAnalyzer()
let silence = [Float](repeating: 0, count: 1024)
let bands = silence.withUnsafeBufferPointer { analyzer.process($0.baseAddress!, count: $0.count, sampleRate: 48000) }
precondition(bands == .zero)

// 10-Band GEQ frequency response check
let centerFreqs = BandAnalyzer.centerFrequencies
for (bandIdx, freq) in centerFreqs.enumerated() {
    var analyzer = BandAnalyzer()
    let samples = (0..<48000).map { Float(sin(2 * Double.pi * Double(freq) * Double($0) / 48000.0)) * 0.5 }
    let (_, geq10) = samples.withUnsafeBufferPointer { analyzer.processDetailed($0.baseAddress!, count: $0.count, sampleRate: 48000) }
    // The targeted band should have significant energy
    precondition(geq10[bandIdx] > 0.15, "Band \(bandIdx) at \(freq)Hz failed to respond: \(geq10)")
}

print("PASS: silence and low/mid/high tones at 44.1 and 48 kHz")
print("PASS: 10-band ISO GEQ filter bank accurate at all 10 center frequencies")

// Interleaved stereo must retain frequency identity without allocating channel copies.
let frameCount = 4096
var interleaved = [Float](repeating: 0, count: frameCount * 2)
for i in 0..<frameCount {
  interleaved[i * 2] = 0.2 * sin(Float(i) * 2 * .pi * 125 / 48000)
  interleaved[i * 2 + 1] = 0.2 * sin(Float(i) * 2 * .pi * 4000 / 48000)
}
var leftAnalyzer = BandAnalyzer()
var rightAnalyzer = BandAnalyzer()
interleaved.withUnsafeBufferPointer { buffer in
  let left = leftAnalyzer.processDetailed(buffer.baseAddress!, count: frameCount, sampleRate: 48000, stride: 2).geq10
  let right = rightAnalyzer.processDetailed(buffer.baseAddress!.advanced(by: 1), count: frameCount, sampleRate: 48000, stride: 2).geq10
  precondition(left[2] > left[7] * 3)
  precondition(right[7] > right[2] * 3)
}
print("PASS: interleaved stereo analysis preserves channel frequencies without deinterleaving copies")
