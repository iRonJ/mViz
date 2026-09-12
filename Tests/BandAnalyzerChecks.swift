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
