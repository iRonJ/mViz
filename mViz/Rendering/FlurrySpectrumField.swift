import RealityKit
import UIKit

/// Fixed GEQ columns plus additive, curling trails. Resources are allocated once.
@MainActor
final class FlurrySpectrumField {
  let root = Entity()
  private var bars: [ModelEntity] = []
  private var wisps: [Entity] = []
  private let mode = FlurrySpectrumMode()

  init(texture: TextureResource?) {
    let mesh = MeshResource.generateBox(size: 1)
    let colors: [UIColor] = [
      .cyan, .systemTeal, .systemBlue, .systemIndigo, .systemPurple,
      .systemPink, .systemOrange, .systemYellow, .systemGreen, .systemMint,
    ]
    for band in 0..<FlurrySpectrumMode.bandCount {
      let color = colors[band]
      let bar = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
      bar.name = "Spectrum band \(band)"
      root.addChild(bar)
      bars.append(bar)

      let wisp = Entity()
      var particles = ParticleEmitterComponent()
      particles.emitterShape = .sphere
      particles.emitterShapeSize = [0.055, 0.025, 0.04]
      particles.particlesInheritTransform = false
      particles.birthDirection = .local
      particles.mainEmitter.image = texture
      particles.mainEmitter.blendMode = .additive
      particles.mainEmitter.birthRate = 0
      particles.mainEmitter.lifeSpan = 3.2
      particles.mainEmitter.size = 0.028
      particles.mainEmitter.sizeVariation = 0.012
      particles.mainEmitter.stretchFactor = 7
      particles.mainEmitter.opacityCurve = .gradualFadeInOut
      particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.1
      particles.mainEmitter.spreadingAngle = 0.12
      particles.mainEmitter.noiseStrength = 0.22
      particles.mainEmitter.noiseScale = 0.65
      particles.mainEmitter.color = .evolving(
        start: .single(color), end: .single(color.withAlphaComponent(0)))
      wisp.components.set(particles)
      root.addChild(wisp)
      wisps.append(wisp)
    }
    root.isEnabled = false
  }

  func update(
    levels: SIMD16<Float>, flux: SIMD16<Float> = .zero, time: Float, weight: Float,
    intensity: Float, speed: Float, reduceMotion: Bool, particleSize: Float,
    transientDynamics: Bool = true
  ) {
    root.isEnabled = weight > 0.001
    guard root.isEnabled else { return }
    root.components.set(OpacityComponent(opacity: weight * min(1, max(0, intensity))))
    let rate = MotionRate(speed).multiplier
    for band in 0..<FlurrySpectrumMode.bandCount {
      let level = levels[band].isFinite ? min(1, max(0, levels[band])) : 0
      let bandFlux = flux[band].isFinite ? min(1, max(0, flux[band])) : 0
      let base = mode.basePosition(band: band)
      let height = mode.barHeight(level: level)
      bars[band].scale = [0.13, height, 0.045]
      bars[band].position = base + SIMD3<Float>(0, height / 2, 0)
      let wisp = wisps[band]
      wisp.position = base + SIMD3<Float>(0, height, 0)
      guard var particles = wisp.components[ParticleEmitterComponent.self] else { continue }
      let phase = Float(band) * 0.63
      particles.emissionDirection = normalize(
        SIMD3<Float>(
          reduceMotion ? 0 : 0.65 * sin(time * 0.55 + phase), 1,
          reduceMotion ? 0 : 0.22 * cos(time * 0.4 + phase)))
      let fluxBoost = transientDynamics ? bandFlux * 0.50 : 0
      particles.speed = (reduceMotion ? 0.08 : 0.08 + pow(level, 1.1) * 0.65 + fluxBoost) * rate

      // Frequency-specific wisp dynamics with rate-of-change transient boost:
      let wispActivity = min(1.0, max(0.0, (level - 0.01) / 0.08))
      let effectiveLevel = transientDynamics ? (level * 0.4 + bandFlux * 0.6) : level
      if band < 3 {
        // Low bands: bass punch pumps particle size
        particles.mainEmitter.size = 0.003 + wispActivity * 0.019 + pow(effectiveLevel, 1.25) * 0.035
        particles.mainEmitter.birthRate =
          (wispActivity * 12 + pow(effectiveLevel, 1.1) * 110) * max(0, min(1, intensity)) * weight
        particles.mainEmitter.noiseStrength = reduceMotion ? 0.02 : 0.15
        particles.mainEmitter.noiseAnimationSpeed = rate * 0.35
      } else if band < 7 {
        // Mid bands: melodic energy surges birth rate on attacks
        particles.mainEmitter.size = 0.003 + wispActivity * 0.017 + effectiveLevel * 0.015
        particles.mainEmitter.birthRate =
          (wispActivity * 15 + pow(effectiveLevel, 1.2) * 180) * max(0, min(1, intensity)) * weight
        particles.mainEmitter.noiseStrength = reduceMotion ? 0.02 : 0.22
        particles.mainEmitter.noiseAnimationSpeed = rate * 0.4
      } else {
        // High bands: high-frequency sizzle and sparkle
        let sizzle = pow(effectiveLevel, 1.2)
        particles.mainEmitter.size = 0.003 + wispActivity * 0.012 + sizzle * 0.012
        particles.mainEmitter.birthRate =
          (wispActivity * 8 + sizzle * 120) * max(0, min(1, intensity)) * weight
        particles.mainEmitter.noiseStrength = reduceMotion ? 0.02 : 0.25 + sizzle * 0.35
        particles.mainEmitter.noiseAnimationSpeed = rate * (0.4 + sizzle * 3.0)
      }

      particles.mainEmitter.size *= particleSize
      particles.mainEmitter.sizeVariation = (0.001 + wispActivity * 0.011) * particleSize
      particles.mainEmitter.lifeSpan = 3.2 / Double(sqrt(rate))
      wisp.components.set(particles)
    }
  }
}
