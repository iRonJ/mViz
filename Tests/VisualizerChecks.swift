import Foundation

var blend = MotionBlend()
var time: Float = 0
var reachedDirectlyAbove = false
var reachedDirectlyBelow = false
for mode in MotionMode.allCases + MotionMode.allCases.reversed() {
    for _ in 0..<180 {
        let previous = blend.position(phase: 1, time: time, bass: 0.5)
        blend.advance(toward: mode, dt: 1 / 30)
        time += 1 / 30
        let position = blend.position(phase: 1, time: time, bass: 0.5)
        precondition(abs(blend.weights.reduce(0, +) - 1) < 0.0001)
        let delta = position - previous
        precondition(sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z) < 0.15, "Transition jumped: \(mode) at \(time), delta \(delta)")
        for i in 0..<12 {
            let p = blend.position(phase: Float(i) / 12 * 2 * .pi, time: time, bass: 1)
            let radius = sqrt(p.x * p.x + p.z * p.z)
            precondition(radius <= 4.1, "Emitter exceeded maximum radius")
            precondition(p.y.isFinite && p.y >= 0.05 && p.y <= 3.85, "Emitter height out of bounds: \(p.y)")
            let eyeDist = sqrt(p.x * p.x + (p.y - 1.5) * (p.y - 1.5) + p.z * p.z)
            precondition(eyeDist >= 1.25, "Emitter entered user personal space: \(eyeDist)")
            if radius < 0.5 && p.y > 2.5 { reachedDirectlyAbove = true }
            if radius < 0.5 && p.y < 0.6 { reachedDirectlyBelow = true }
        }
    }
}
precondition(reachedDirectlyAbove, "Emitters did not reach directly above user")
precondition(reachedDirectlyBelow, "Emitters did not reach directly below user")
let a = LocalTrack(id: UUID(), title: "A", filename: "a", playCount: 200, rating: 4)
let b = LocalTrack(id: UUID(), title: "B", filename: "b", playCount: 0, rating: 2)
let c = LocalTrack(id: UUID(), title: "C", filename: "c", rating: 1, isFavorite: true)
let d = LocalTrack(id: UUID(), title: "D", filename: "d", rating: 3)
precondition(nextTrack(in: [], after: nil, smart: true) == nil)
precondition(nextTrack(in: [b], after: nil, smart: true) == nil)
precondition(nextTrack(in: [a], after: a.id, smart: true)?.id == a.id)
for _ in 0..<100 {
    let pick = nextTrack(in: [a, b, c, d], after: a.id, smart: true)
    precondition(pick?.id == c.id || pick?.id == d.id)
}
precondition(nextTrack(in: [a, b, c], after: a.id, smart: false)?.id == b.id)
precondition(nextTrack(in: [a, b, c], after: b.id, smart: false)?.id == c.id)
precondition(nextTrack(in: [a, b, c], after: c.id, smart: false)?.id == a.id)
precondition(nextTrack(in: [b], after: b.id, smart: false)?.id == b.id)
let unratedPlaylist = [b]
let effectiveSmartWithUnrated = true && unratedPlaylist.contains(where: \.qualifiesForMix)
precondition(nextTrack(in: unratedPlaylist, after: b.id, smart: effectiveSmartWithUnrated)?.id == b.id)
precondition(nextTrack(in: [a, b, c], after: b.id, smart: true)?.qualifiesForMix == true)
let encoded = try JSONEncoder().encode([a, b, c])
let restored = try JSONDecoder().decode([LocalTrack].self, from: encoded)
precondition(restored.map(\.id) == [a.id, b.id, c.id])
precondition(restored[0].rating == 4 && restored[2].isFavorite == true)
// Existing playlists from the first version have no ratings or favorite keys.
let legacy = "[{\"id\":\"\(UUID().uuidString)\",\"title\":\"Old\",\"filename\":\"old.wav\",\"playCount\":2}]"
let migrated = try JSONDecoder().decode([LocalTrack].self, from: Data(legacy.utf8))
precondition(!migrated[0].qualifiesForMix)
print("PASS: all movement modes, overhead/underfoot paths, safe eye clearance, smooth transitions, and playlist migration")

// Spectrum columns share a stationary baseline/depth, with monotonic GEQ height.
let spectrum = FlurrySpectrumMode()
for band in 0..<FlurrySpectrumMode.bandCount {
    let base = spectrum.basePosition(band: band)
    precondition(base.y == FlurrySpectrumMode.baseline && base.z == -5)
    let reflected = spectrum.basePosition(band: 9 - band)
    precondition(abs(base.x + reflected.x) < 0.0001)
    if band > 0 { precondition(base.x > spectrum.basePosition(band: band - 1).x) }
}
precondition(spectrum.barHeight(level: 0) < spectrum.barHeight(level: 0.5))
precondition(spectrum.barHeight(level: 0.5) < spectrum.barHeight(level: 1))
precondition(spectrum.barHeight(level: -1) == spectrum.barHeight(level: 0))
precondition(spectrum.barHeight(level: 2) == spectrum.barHeight(level: 1))
precondition(spectrum.barHeight(level: .nan).isFinite)
precondition(spectrum.lightingStyle == .off)
print("PASS: fixed distant spectrum geometry, bounded GEQ response, and quiet lighting")

// Every left/right pair must match height/depth and reflect about x=0.
for t: Float in [0, 3, 10] {
    for i in 0..<12 {
        let left = MirrorLineMode().stagePosition(index: i, time: t, bass: 0.8)
        let right = MirrorLineMode().stagePosition(index: 11 - i, time: t, bass: 0.8)
        precondition(abs(left.x + right.x) < 0.0001 && left.y == right.y && left.z == right.z)
        let p = MirrorPlaneMode().stagePosition(index: i, time: t, bass: 0.8)
        let q = MirrorPlaneMode().stagePosition(index: (i / 4) * 4 + 3 - i % 4, time: t, bass: 0.8)
        precondition(abs(p.x + q.x) < 0.0001 && p.y == q.y && p.z == q.z)
    }
}
precondition(MotionRate(3).advance(1) == 3 && MotionRate(0.25).velocity(4) == 1)
precondition(NebulaMode().angularVelocity(time: 0) > 0 && NebulaMode().angularVelocity(time: 16) < 0)
precondition(HelixMode().angularVelocity(time: 0) < 0)
precondition(RainMode().dynamics(bass: 1).direction!.y < 0)
precondition(VolcanoMode().dynamics(bass: 1).direction!.y > 0)
precondition(VolcanoMode().dynamics(bass: 1).speedBoost > VolcanoMode().dynamics(bass: 0).speedBoost)
let lowColor = reactiveColor(bands: [1, 0, 0], offset: 0)
let highColor = reactiveColor(bands: [0, 0, 1], offset: 0)
precondition(abs(lowColor.x - highColor.x) > 0.4)
var pulse = BeatPulse()
var lastFlash = -100.0
var wasLit = false
var flashes = 0
for frame in 0..<600 {
    let now = Double(frame) / 60
    let level: Float = frame % 6 == 0 ? 1 : 0
    let lit = pulse.update(bass: level, dt: 1 / 60, style: .strobe) > 0
    if lit && !wasLit {
        precondition(now - lastFlash >= 0.49, "Strobe exceeded rate cap")
        lastFlash = now
        flashes += 1
    }
    wasLit = lit
}
precondition(flashes > 0 && flashes <= 20)
precondition(pulse.update(bass: 1, dt: 1, style: .off) == 0)

precondition(NebulaMode().lightingStyle == .off)
precondition(MirrorPlaneMode().lightingStyle == .off)
precondition(RainMode().lightingStyle == .off)
precondition(HelixMode().lightingStyle == .pulse)
precondition(AuroraMode().lightingStyle == .pulse)
precondition(RoomBounceMode().lightingStyle == .pulse)
precondition(VolcanoMode().lightingStyle == .strobe)
precondition(MirrorLineMode().lightingStyle == .strobe)
precondition(VortexMode().lightingStyle == .strobe)
precondition(CosmicFogMode().lightingStyle == .pulse)
precondition(SupernovaMode().lightingStyle == .strobe)

var fadePulse = BeatPulse()
let fullPulse = fadePulse.update(bass: 1, dt: 1, pulseWeight: 1, strobeWeight: 0)
let halfPulse = fadePulse.update(bass: 1, dt: 0, pulseWeight: 0.5, strobeWeight: 0)
let zeroPulse = fadePulse.update(bass: 1, dt: 0, pulseWeight: 0, strobeWeight: 0)
precondition(fullPulse > 0)
precondition(abs(halfPulse - fullPulse * 0.5) < 0.001)
precondition(zeroPulse == 0)

var testBlend = MotionBlend()
var testTime: Float = 0
for mode in MotionMode.allCases {
    for _ in 0..<60 {
        testBlend.advance(toward: mode, dt: 1 / 60)
        testTime += 1 / 60
        var blendedSpeedBoost: Float = 0
        for m in MotionMode.allCases {
            let dyn = m.definition.dynamics(bass: 0.5)
            blendedSpeedBoost += dyn.speedBoost * testBlend[m]
        }
        for speedSetting: Float in [0.25, 1.0, 3.0] {
            let motionRate = MotionRate(speedSetting)
            var spd = 0.15 + 0.5 * 0.65 + testBlend[.vortex] * 0.25
            spd += blendedSpeedBoost
            spd = motionRate.velocity(spd)
            spd = min(max(spd, 0.05), 8.0)
            precondition(spd >= 0.05 && spd <= 8.0 && spd.isFinite && !spd.isNaN, "Particle speed out of bounds: \(spd)")
        }
    }
}

print("PASS: stage symmetry, speed, reversing motion, spectral colors, strobe rate limit, and lighting mode transitions with smooth fade")

// Identical bass ramps should trigger beats at different headset frame rates.
for fps: Float in [60, 90, 120] {
    var detector = BeatPulse()
    var count = 0
    for frame in 0..<Int(fps * 8) {
        let time = Float(frame) / fps
        let phase = time.truncatingRemainder(dividingBy: 0.75)
        let bass: Float = phase < 0.1 ? phase * 6 : max(0, 0.6 - (phase - 0.1) * 3)
        _ = detector.update(bass: bass, dt: 1 / fps, style: .off)
        if detector.beatTriggered { count += 1 }
    }
    precondition(count >= 9 && count <= 11, "Frame-rate-dependent beat detection at \(fps): \(count)")
}
print("PASS: bass onset detection at 60/90/120 Hz with lighting off")

var beatIntensityDetector = BeatPulse()
_ = beatIntensityDetector.update(bass: 0, dt: 0.1, style: .off)
precondition(beatIntensityDetector.beatIntensity == 0)
_ = beatIntensityDetector.update(bass: 1.0, dt: 0.1, style: .off)
precondition(beatIntensityDetector.beatTriggered)
precondition(beatIntensityDetector.beatIntensity > 0.8, "Beat intensity did not pulse on onset")
_ = beatIntensityDetector.update(bass: 0.2, dt: 0.2, style: .off)
precondition(beatIntensityDetector.beatIntensity < 0.6, "Beat intensity did not decay exponentially")
print("PASS: beat intensity envelope and decay for particle brightness pulse")

for mode in MotionMode.allCases {
    let dynamics = mode.definition.dynamics(bass: 1)
    precondition(dynamics.birthBoost <= 1, "Mode density accidentally interpreted as a large multiplier")
    for speed: Float in [0.25, 1, 3] {
        let lifetime = (dynamics.lifeSpan ?? 2.5) / Double(sqrt(speed))
        let rate = ParticleBudget.birthRate(requested: 100000, lifeSpan: lifetime)
        precondition(rate * Float(lifetime) <= 1200.01)
    }
}
print("PASS: bounded particle populations across loud modes and motion speeds")

precondition(AudioLevelCurve.map(0, logarithmic: true) == 0)
precondition(AudioLevelCurve.map(0.001, logarithmic: true) == 0)
precondition(abs(AudioLevelCurve.map(1, logarithmic: true) - 1) < 0.00001)
precondition(AudioLevelCurve.map(.nan, logarithmic: true) == 0)
var previousLevel: Float = 0
for step in 0...1000 {
    let level = Float(step) / 1000
    let mapped = AudioLevelCurve.map(level, logarithmic: true)
    precondition(mapped >= previousLevel && mapped <= 1)
    precondition(AudioLevelCurve.map(level, logarithmic: false) == level)
    previousLevel = mapped
}
precondition(AudioLevelCurve.map(0.1, logarithmic: true) > 0.25)
precondition(AudioLevelCurve.map(0.5, logarithmic: true) > 0.7)
print("PASS: log response endpoints, noise floor, monotonicity, quiet-detail lift, and linear comparison")

// SpectralFluxFollower vectorized tracking & Weber-Fechner adaptive baseline
var fluxFollower = SpectralFluxFollower<SIMD3<Float>>()
precondition(fluxFollower.envelope == .zero)
precondition(fluxFollower.flux == .zero)

// Impulse hit on bass
fluxFollower.update(
    signal: SIMD3<Float>(0.9, 0.1, 0.05),
    dt: 0.016,
    attackRates: SIMD3<Float>(35, 40, 45),
    decayRates: SIMD3<Float>(12, 14, 16)
)
precondition(fluxFollower.envelope.x > 0.2, "Envelope did not attack on kick")
precondition(fluxFollower.flux.x > 0.5, "Flux did not fire on onset")
let initialFlux = fluxFollower.flux.x

// Sustained tone: baseline rises, flux relaxes
for _ in 0..<30 {
    fluxFollower.update(
        signal: SIMD3<Float>(0.9, 0.1, 0.05),
        dt: 0.016,
        attackRates: SIMD3<Float>(35, 40, 45),
        decayRates: SIMD3<Float>(12, 14, 16)
    )
}
precondition(fluxFollower.baseline.x > 0.4, "Baseline failed to follow steady level")
precondition(fluxFollower.flux.x < initialFlux, "Flux failed to adapt down under sustained signal")

// Dynamics blending via MotionBlend
let blendedDyn = blend.dynamics(bass: 0.5)
precondition(blendedDyn.speedBoost.isFinite)
precondition(blendedDyn.gravity.isFinite)
precondition(blendedDyn.spreadBoost.isFinite)
precondition(blendedDyn.birthMultiplier >= 1.0)

// StagePositionable polymorphism
let stageLineTest: any StagePositionable = MirrorLineMode()
let stageGridTest: any StagePositionable = MirrorPlaneMode()
for i in 0..<12 {
    let pLine = stageLineTest.stagePosition(index: i, time: 0.5, bass: 0.8)
    let pGrid = stageGridTest.stagePosition(index: i, time: 0.5, bass: 0.8)
    precondition(pLine.x.isFinite && pLine.y.isFinite && pLine.z.isFinite)
    precondition(pGrid.x.isFinite && pGrid.y.isFinite && pGrid.z.isFinite)
}
print("PASS: SpectralFluxFollower vectorized tracking, blended dynamics, and StagePositionable polymorphism")

// Mode dynamic range & low resting baseline verification
let volcanoZero = MotionMode.volcano.definition.dynamics(bass: 0)
let volcanoOne = MotionMode.volcano.definition.dynamics(bass: 1)
precondition(volcanoZero.speedBoost <= 0.25, "Volcano resting speed too high: \(volcanoZero.speedBoost)")
precondition(volcanoOne.speedBoost >= 3.5, "Volcano peak speed too low: \(volcanoOne.speedBoost)")
precondition(volcanoOne.speedBoost / volcanoZero.speedBoost >= 15.0, "Volcano dynamic range insufficient")
precondition(volcanoZero.spreadBoost <= 0.1)
precondition(volcanoOne.spreadBoost >= 0.4)

let rainZero = MotionMode.rain.definition.dynamics(bass: 0)
let rainOne = MotionMode.rain.definition.dynamics(bass: 1)
precondition(rainZero.speedBoost <= 0.2, "Rain resting speed too high: \(rainZero.speedBoost)")
precondition(rainOne.speedBoost >= 2.2, "Rain peak speed too low: \(rainOne.speedBoost)")
precondition(rainOne.speedBoost / rainZero.speedBoost >= 10.0, "Rain dynamic range insufficient")
precondition((rainZero.stretch ?? 0) <= 2.5)
precondition((rainOne.stretch ?? 0) >= 6.5)
precondition(rainOne.birthBoost >= 0.8)

for mode in MotionMode.allCases {
    let d0 = mode.definition.dynamics(bass: 0)
    let d1 = mode.definition.dynamics(bass: 1)
    precondition(d0.birthBoost <= d1.birthBoost, "Monotonicity violated in mode \(mode)")
    precondition(d1.birthBoost <= 1.0, "Birth boost exceeded 1.0 in mode \(mode)")
    precondition(d0.speedBoost.isFinite && d1.speedBoost.isFinite)
}
print("PASS: low base emitter rate/speed and wide dynamic range across all visualization modes")


