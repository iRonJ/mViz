import RealityKit
import SwiftUI
import UIKit

/// Twelve GPU emitters with bounded birth rates and lifetimes.
@MainActor
final class ParticleField {
  let root = Entity()
  let stageRoot = Entity()
  var stageAnchor = AnchorEntity(.head, trackingMode: .once)
  var stageEmitters: [Entity] = []
  var flurry: FlurrySpectrumField!
  var textures: [ParticleStyle: TextureResource] = [:]

  func recenterStage() {
    let previous = stageAnchor
    stageAnchor = AnchorEntity(.head, trackingMode: .once)
    stageRoot.addChild(stageAnchor)
    for emitter in stageEmitters { stageAnchor.addChild(emitter) }
    if let flurry { stageAnchor.addChild(flurry.root) }
    previous.removeFromParent()
  }

  var emitters: [Entity] = []
  var time: Float = 0
  var journeyTime: Float = 0
  var shapeTime: Float = 0
  var envelope = SIMD3<Float>.zero
  private var linearBassEnvelope: Float = 0
  var geq10Envelope = SIMD16<Float>.zero
  private var previousSignal = SIMD3<Float>.zero
  private var baselineFollower = SIMD3<Float>.zero
  var fluxEnvelope = SIMD3<Float>.zero
  private var previousSignal10 = SIMD16<Float>.zero
  private var baselineFollower10 = SIMD16<Float>.zero
  var geq10FluxEnvelope = SIMD16<Float>.zero
  var blend = MotionBlend()
  var activeMode = MotionMode.orbit
  var wasAutomatic = true
  var currentForm = EmitterForm.sphere
  var shapeScale: Float = 1
  let environment = RoomEnvironment()
  let backgroundGlow: ModelEntity
  var beatPulse = BeatPulse()
  var roomParticles: [(entity: ModelEntity, age: Float)] = []
  var spawnBudget: Float = 0
  var surfacesAvailable = false
  var roomMaterials: [UnlitMaterial] = []
  var lastRoomEnvelope = SIMD3<Float>(-1, -1, -1)
  private var lastGlowOpacity: Float = -1
  private var lastGlowColor: UIColor?
  private var stageEmittersActive = true
  private var orbitEmittersActive = true

  init() {
    var glowMaterial = UnlitMaterial(color: .white)
    glowMaterial.faceCulling = .front
    backgroundGlow = ModelEntity(mesh: .generateSphere(radius: 15), materials: [glowMaterial])
    backgroundGlow.components.set(OpacityComponent(opacity: 0))
    root.addChild(backgroundGlow)
    root.addChild(environment.root)
    stageRoot.addChild(stageAnchor)
    for style in ParticleStyle.allCases where style != .evolving {
      textures[style] = makeTexture(style)
    }
    flurry = FlurrySpectrumField(texture: textures[.glow])
    stageAnchor.addChild(flurry.root)
    let mesh = MeshResource.generateSphere(radius: 0.028)
    let shape = ShapeResource.generateSphere(radius: 0.028)
    let material = PhysicsMaterialResource.generate(friction: 0.1, restitution: 0.85)
    roomMaterials = (0..<8).map { b in
      UnlitMaterial(color: UIColor(hue: CGFloat(b) / 8, saturation: 0.65, brightness: 1, alpha: 1))
    }
    for index in 0..<96 {
      let particle = ModelEntity(mesh: mesh, materials: [roomMaterials[index % 8]])
      particle.components.set(
        CollisionComponent(
          shapes: [shape], filter: CollisionFilter(group: .default, mask: .sceneUnderstanding)))
      var body = PhysicsBodyComponent(
        shapes: [shape], mass: 0.01, material: material, mode: .dynamic)
      body.isContinuousCollisionDetectionEnabled = true
      particle.components.set(body)
      particle.isEnabled = false
      root.addChild(particle)
      roomParticles.append((particle, 0))
    }
    for index in 0..<12 {
      let entity = Entity()
      var particles = ParticleEmitterComponent()
      particles.emitterShape = .sphere
      particles.emitterShapeSize = EmitterForm.sphere.dimensions
      particles.birthLocation = .surface
      particles.particlesInheritTransform = false
      particles.mainEmitter.blendMode = .additive
      particles.mainEmitter.birthRate = 100
      particles.mainEmitter.lifeSpan = 2.5
      particles.mainEmitter.size = 0.018
      particles.mainEmitter.sizeVariation = 0.012
      particles.mainEmitter.color = .evolving(start: .single(.cyan), end: .single(.purple))
      particles.speed = 0.2
      entity.components.set(particles)
      entity.position = blend.position(phase: Float(index) / 12 * 2 * .pi, time: 0, bass: 0)
      entity.name = "Orbit \(index)"
      root.addChild(entity)
      emitters.append(entity)
      let stage = Entity()
      particles.mainEmitter.birthRate = 0
      stage.components.set(particles)
      stage.position = MirrorLineMode().stagePosition(index: index, time: 0, bass: 0)
      stageAnchor.addChild(stage)
      stageEmitters.append(stage)
    }
  }

  private static let evolvingForms: [EmitterForm] = [.sphere, .torus, .plane, .cone, .box]
  private static let evolvingStyles: [ParticleStyle] = [.glow, .sparks, .rings, .flakes]

  func update(dt: Float, model: VisualizerModel) {
    let dt = min(max(dt, 0), 0.1)
    let motionRate = MotionRate(model.motionSpeed)
    time += motionRate.advance(dt)
    shapeTime += dt
    if model.automaticModes {
      if !wasAutomatic { journeyTime = 0 }
      journeyTime += dt
      if journeyTime >= 18 {
        journeyTime = 0
        let index = MotionMode.allCases.firstIndex(of: activeMode) ?? 0
        activeMode = MotionMode.allCases[(index + 1) % MotionMode.allCases.count]
        if activeMode == .room && (!model.roomEnabled || !model.roomReady) { activeMode = .orbit }
      }
    } else {
      activeMode = model.motion
      journeyTime = 0
    }
    if activeMode == .room && !model.roomEnabled { activeMode = .orbit }
    wasAutomatic = model.automaticModes
    if model.activeMotion != activeMode {
      if (activeMode == .line || activeMode == .grid || activeMode == .flurry)
        && model.activeMotion != .line && model.activeMotion != .grid
        && model.activeMotion != .flurry
      {
        recenterStage()
      }
      model.activeMotion = activeMode
    }
    blend.advance(toward: activeMode, dt: dt, speed: model.motionSpeed)

    let desiredForm =
      model.shape == .evolving
      ? Self.evolvingForms[Int(shapeTime / 8) % Self.evolvingForms.count] : model.shape
    // Collapse the emission surface, change topology, then expand. Existing
    // particles keep their world-space trails throughout the transition.
    if desiredForm != currentForm {
      shapeScale = max(0.02, shapeScale - dt * 2)
      if shapeScale <= 0.02 { currentForm = desiredForm }
    } else {
      shapeScale = min(1, shapeScale + dt * 1.5)
    }

    let raw = model.bands * model.sensitivity * 8
    let signal = SIMD3<Float>(
      AudioLevelCurve.map(raw.x, logarithmic: model.logarithmicLevels),
      AudioLevelCurve.map(raw.y, logarithmic: model.logarithmicLevels),
      AudioLevelCurve.map(raw.z, logarithmic: model.logarithmicLevels))
    // Keep onset detection independent of visual compression and A/B changes.
    let linearBass = AudioLevelCurve.map(raw.x, logarithmic: false)
    let bassRate: Float = linearBass > linearBassEnvelope ? 55 : 12
    linearBassEnvelope += (linearBass - linearBassEnvelope) * (1 - exp(-dt * bassRate))
    // Tuned attack and decay rates per frequency register:
    // Bass: punchy attack 50, solid decay 12
    // Mid: agile attack 55, flowing decay 16
    // Treble: razor-sharp attack 70, transient decay 24
    let attackRates: SIMD3<Float> = [50, 55, 70]
    let decayRates: SIMD3<Float> = [12, 16, 24]
    for i in 0..<3 {
      let rate: Float = signal[i] > envelope[i] ? attackRates[i] : decayRates[i]
      envelope[i] += (signal[i] - envelope[i]) * (1 - exp(-dt * rate))
    }
    model.geqLevels = envelope

    // Macro bands flux (rate-of-change & adaptive contrast follower):
    let dtClamped = max(0.005, dt)
    let rawDelta = max(SIMD3<Float>.zero, signal - previousSignal)
    let instantDerivative = min(SIMD3<Float>(repeating: 1.0), (rawDelta / dtClamped) * 0.22)
    previousSignal = signal

    for i in 0..<3 {
      let baseRate: Float = signal[i] > baselineFollower[i] ? 2.5 : 1.8
      baselineFollower[i] += (signal[i] - baselineFollower[i]) * (1 - exp(-dt * baseRate))
      let contrast = max(0, signal[i] - baselineFollower[i]) / max(0.2, 1.0 - baselineFollower[i] * 0.5)
      let targetFlux = min(1.0, max(instantDerivative[i], contrast * 0.9))
      let fluxRate: Float = targetFlux > fluxEnvelope[i] ? 65 : 16
      fluxEnvelope[i] += (targetFlux - fluxEnvelope[i]) * (1 - exp(-dt * fluxRate))
    }
    model.macroFlux = fluxEnvelope

    let raw10 = model.bands10 * model.sensitivity * 8
    var sig10 = SIMD16<Float>.zero
    for i in 0..<10 {
      let sig = AudioLevelCurve.map(raw10[i], logarithmic: model.logarithmicLevels)
      sig10[i] = sig
      let attack: Float = i < 3 ? 50 : (i < 7 ? 55 : 70)
      let decay: Float = i < 3 ? 12 : (i < 7 ? 16 : 24)
      let rate: Float = sig > geq10Envelope[i] ? attack : decay
      geq10Envelope[i] += (sig - geq10Envelope[i]) * (1 - exp(-dt * rate))

      // 10-band rate-of-change flux:
      let rawDelta10 = max(0, sig - previousSignal10[i])
      let instant10 = min(1.0, (rawDelta10 / dtClamped) * 0.22)
      let baseRate10: Float = sig > baselineFollower10[i] ? 2.5 : 1.8
      baselineFollower10[i] += (sig - baselineFollower10[i]) * (1 - exp(-dt * baseRate10))
      let contrast10 = max(0, sig - baselineFollower10[i]) / max(0.2, 1.0 - baselineFollower10[i] * 0.5)
      let targetFlux10 = min(1.0, max(instant10, contrast10 * 0.9))
      let fluxRate10: Float = targetFlux10 > geq10FluxEnvelope[i] ? 65 : 16
      geq10FluxEnvelope[i] += (targetFlux10 - geq10FluxEnvelope[i]) * (1 - exp(-dt * fluxRate10))
    }
    previousSignal10 = sig10
    model.geq10Levels = geq10Envelope
    model.geq10Flux = geq10FluxEnvelope
    let pulseWeight: Float
    let strobeWeight: Float
    switch model.beatLighting {
    case .off:
      pulseWeight = 0
      strobeWeight = 0
    case .pulse:
      pulseWeight = 1
      strobeWeight = 0
    case .strobe:
      if model.reduceMotion {
        pulseWeight = 1
        strobeWeight = 0
      } else {
        pulseWeight = 0
        strobeWeight = 1
      }
    case .evolving:
      var pWeight: Float = 0
      var sWeight: Float = 0
      for mode in MotionMode.allCases {
        let w = blend[mode]
        guard w > 0.001 else { continue }
        switch mode.definition.lightingStyle {
        case .off: break
        case .pulse: pWeight += w
        case .strobe: sWeight += w
        case .evolving: pWeight += w
        }
      }
      if model.reduceMotion {
        pulseWeight = pWeight + sWeight
        strobeWeight = 0
      } else {
        pulseWeight = pWeight
        strobeWeight = sWeight
      }
    }
    let pulse = beatPulse.update(
      bass: linearBassEnvelope, dt: dt, pulseWeight: pulseWeight, strobeWeight: strobeWeight)
    let hsv = reactiveColor(bands: envelope, offset: 0)
    let lightColor = UIColor(hue: CGFloat(hsv.x), saturation: 0.65, brightness: 1, alpha: 1)
    environment.illuminate(
      color: lightColor, opacity: model.passthrough ? pulse * model.lightingIntensity : 0)
    let glowOpacity = model.passthrough ? 0 : pulse * model.lightingIntensity
    if glowOpacity > 0.001 {
      if abs(glowOpacity - lastGlowOpacity) > 0.005 || lightColor != lastGlowColor {
        var material = UnlitMaterial(color: lightColor)
        material.faceCulling = .front
        backgroundGlow.model?.materials = [material]
        backgroundGlow.components.set(OpacityComponent(opacity: glowOpacity))
        lastGlowOpacity = glowOpacity
        lastGlowColor = lightColor
      }
    } else if lastGlowOpacity > 0.001 {
      backgroundGlow.components.set(OpacityComponent(opacity: 0))
      lastGlowOpacity = 0
    }
    let style =
      model.particleStyle == .evolving
      ? Self.evolvingStyles[Int(shapeTime / 12) % Self.evolvingStyles.count] : model.particleStyle
    flurry.update(
      levels: geq10Envelope, flux: geq10FluxEnvelope, time: time, weight: blend[.flurry],
      intensity: model.intensity, speed: model.motionSpeed, reduceMotion: model.reduceMotion,
      particleSize: model.particleSize, transientDynamics: model.transientDynamics)
    let stageWeight = blend[.line] + blend[.grid]
    let frontWeight = min(1, stageWeight + blend[.flurry])
    if stageWeight < 0.001 {
      if stageEmittersActive {
        for stage in stageEmitters {
          guard var p = stage.components[ParticleEmitterComponent.self] else { continue }
          p.mainEmitter.birthRate = 0
          stage.components.set(p)
        }
        stageEmittersActive = false
      }
    } else {
      stageEmittersActive = true
    }

    if frontWeight > 0.999 {
      if orbitEmittersActive {
        for entity in emitters {
          guard var p = entity.components[ParticleEmitterComponent.self] else { continue }
          p.mainEmitter.birthRate = 0
          entity.components.set(p)
        }
        orbitEmittersActive = false
      }
    } else {
      orbitEmittersActive = true
    }

    var blendedDirection = SIMD3<Float>.zero
    var blendedDirectionWeight: Float = 0
    var blendedSpeedBoost: Float = 0
    var blendedGravity: Float = 0
    var blendedSpreadBoost: Float = 0
    var blendedBirthMultiplier: Float = 1
    for mode in MotionMode.allCases {
      let weight = blend[mode]
      guard weight > 0.001 else { continue }
      let dynamics = mode.definition.dynamics(bass: envelope.x)
      if let target = dynamics.direction {
        blendedDirection += target * weight
        blendedDirectionWeight += weight
      }
      blendedSpeedBoost += dynamics.speedBoost * weight
      blendedGravity += dynamics.gravity * weight
      blendedSpreadBoost += dynamics.spreadBoost * weight
      blendedBirthMultiplier += dynamics.birthBoost * weight
    }

    updateRoom(dt: dt, weight: blend[.room], model: model)
    let activeDynamics = activeMode.definition.dynamics(bass: envelope.x)
    let planeWeight = stageWeight > 0.001 ? blend[.grid] / stageWeight : 0
    let useFlux = model.transientDynamics
    let bassPunch: Float = useFlux
      ? (pow(envelope.x, 1.3) * 0.35 + pow(fluxEnvelope.x, 1.2) * 0.65)
      : pow(envelope.x, 1.25)
    let midDensity: Float = useFlux
      ? (pow(envelope.y, 1.2) * 0.35 + pow(fluxEnvelope.y, 1.2) * 0.65)
      : pow(envelope.y, 1.2)
    let midSpeed: Float = useFlux
      ? (pow(envelope.y, 1.1) * 0.40 + pow(fluxEnvelope.y, 1.1) * 0.60)
      : pow(envelope.y, 1.1)
    let totalEnergy = max(linearBassEnvelope, max(envelope.x, max(envelope.y, envelope.z)))
    let activity = min(1.0, max(0.0, (totalEnergy - 0.008) / 0.10))
    let beatPulseIntensity = beatPulse.beatIntensity
    for index in 0..<12 {
      let entity = emitters[index]
      let stage = stageEmitters[index]
      let phase = Float(index) / 12 * 2 * .pi
      guard var particles = entity.components[ParticleEmitterComponent.self] else { continue }

      let currentPos = blend.position(phase: phase, time: time, bass: envelope.x)

      particles.emitterShape = currentForm.shape
      let lowBandBoost: Float = index < 3
        ? (useFlux ? (pow(geq10Envelope[index], 1.2) * 0.4 + pow(geq10FluxEnvelope[index], 1.2) * 0.6) : pow(geq10Envelope[index], 1.2))
        : 0
      let midBandBoost: Float = (index >= 3 && index <= 6)
        ? (useFlux ? (pow(geq10Envelope[index], 1.15) * 0.4 + pow(geq10FluxEnvelope[index], 1.15) * 0.6) : pow(geq10Envelope[index], 1.15))
        : 0
      let highBandBoost: Float = (index >= 7 && index <= 9)
        ? (useFlux ? (pow(geq10Envelope[index], 1.2) * 0.3 + pow(geq10FluxEnvelope[index], 1.2) * 0.7) : pow(geq10Envelope[index], 1.2))
        : 0

      let highEnergy = max(envelope.z, highBandBoost)
      let highFlux = max(fluxEnvelope.z, (index >= 7 && index <= 9) ? geq10FluxEnvelope[index] : fluxEnvelope.z)
      let trebleSizzle = pow(useFlux ? (highEnergy * 0.3 + highFlux * 0.7) : highEnergy, 1.25)

      // 1. Bass tracks particle size and emitter shape expansion
      particles.emitterShapeSize = currentForm.dimensions * shapeScale * (0.85 + bassPunch * 0.75)
      particles.torusInnerRadius = 0.7
      let aurora = blend[.aurora]
      let vortex = blend[.vortex]
      let bandEnergy: Float =
        index < 10 ? geq10Envelope[index] : (index == 10 ? envelope.x : envelope.z)

      // 2. Mid-range frequencies track particle emission rate & density (whisper floor in silence)
      let baseFloor = 2.0 + activity * 18.0
      var baseBirthRate =
        (baseFloor + midDensity * 360 + midBandBoost * 140 + bandEnergy * 50) * model.intensity
        * (1 - blend[.room] * (surfacesAvailable ? 0.85 : 0))
      if index >= 3 && index <= 6 {
        baseBirthRate *= 1.25  // Melodic mid-frequency emitters carry extra lush density
      }

      particles.mainEmitter.lifeSpan = Double(2.5 + aurora * 0.8)

      // Particle size expands with punchy bass hits and pulses directly on the beat!
      // In silence/quiet: drops to 0.002m (tiny specks). Active: scales up to 0.050m+ on kicks.
      let baseParticleSize: Float = 0.002 + activity * 0.006
      var dynamicSize: Float =
        (baseParticleSize + bassPunch * 0.034 + beatPulseIntensity * 0.018 + lowBandBoost * 0.016)
        * activeDynamics.sizeScale
      if index < 3 {
        dynamicSize *= 1.35  // Bass/sub-bass emitters form heavier celestial bodies
      }
      particles.mainEmitter.size = dynamicSize

      let horizontalDist = sqrt(
        currentPos.x * currentPos.x + currentPos.z * currentPos.z)
      let angle = horizontalDist > 0.001 ? atan2(currentPos.z, currentPos.x) : phase
      let dy = currentPos.y - 1.5
      let verticalBias: Float = dy > 1.0 ? -0.3 : (dy < -0.8 ? 0.4 : 0)
      particles.birthDirection = .world
      let rawDir = SIMD3<Float>(
        cos(angle + .pi / 2),
        aurora * 0.8 + sin(time + phase) * 0.3 + verticalBias,
        sin(angle + .pi / 2)
      )
      let rawDirLen = length(rawDir)
      particles.emissionDirection = rawDirLen > 0.001 ? rawDir / rawDirLen : [0, 1, 0]

      // 3. High-frequency color sizzle & beat-driven palette rotation with brightness pulse and silence dimming
      let baseEmitterHue = Float(index) / 12.0 + aurora * 0.15
      let (emitterStartColor, emitterEndColor) = reactiveEmitterColors(
        baseHue: baseEmitterHue,
        bands: envelope,
        highFrequency: useFlux ? (highEnergy * 0.3 + highFlux * 0.7) : highEnergy,
        hueOffset: beatPulse.paletteHue,
        beatPulse: beatPulseIntensity,
        activity: activity
      )
      particles.mainEmitter.color = .evolving(
        start: .single(emitterStartColor), end: .single(emitterEndColor))
      particles.mainEmitter.acceleration = .zero

      // Mid frequencies propel velocity and forward swirl
      particles.speed = 0.12 + midSpeed * 0.85 + vortex * 0.25
      particles.speed += blendedSpeedBoost
      particles.mainEmitter.acceleration.y += blendedGravity
      particles.mainEmitter.birthRate = baseBirthRate * blendedBirthMultiplier

      if blendedDirectionWeight > 0.001 {
        particles.emissionDirection =
          particles.emissionDirection * (1 - blendedDirectionWeight) + blendedDirection
        let finalDirLen = length(particles.emissionDirection)
        if finalDirLen > 0.001 {
          particles.emissionDirection /= finalDirLen
        }
      }

      if model.shape == .evolving, let form = activeDynamics.form {
        particles.emitterShape = form == .plane ? .plane : .cone
        particles.emitterShapeSize = form == .plane ? [1.2, 0.02, 1.2] : [0.3, 0.3, 0.3]
        entity.orientation = simd_quatf()
      }
      applyStyle(style, to: &particles)
      // Sizzle micro-noise and dynamic spreading on high frequencies
      particles.mainEmitter.noiseStrength =
        0.03 + trebleSizzle * 0.35 + (index >= 7 && index <= 9 ? 0.15 : 0)
      particles.mainEmitter.noiseAnimationSpeed = motionRate.multiplier * (1.0 + trebleSizzle * 3.5)
      particles.mainEmitter.spreadingAngle = 0.28 + trebleSizzle * 0.22 + blendedSpreadBoost

      if let stretch = activeDynamics.stretch { particles.mainEmitter.stretchFactor = stretch }
      if let lifeSpan = activeDynamics.lifeSpan { particles.mainEmitter.lifeSpan = lifeSpan }
      if index >= 7 && index <= 9 {
        particles.mainEmitter.stretchFactor *= (1.0 + trebleSizzle * 1.5)
      }

      if activeMode == .volcano {
        let magmaHue = CGFloat(
          (0.02 + envelope.x * 0.10 + trebleSizzle * 0.05 + beatPulse.paletteHue * 0.15)
            .truncatingRemainder(dividingBy: 1.0))
        let magmaBrightness = CGFloat(min(1.0, 0.18 + activity * 0.47 + beatPulseIntensity * 0.35))
        let magmaStart = UIColor(
          hue: magmaHue >= 0 ? magmaHue : magmaHue + 1.0,
          saturation: CGFloat(max(0.2, 0.85 - trebleSizzle * 0.55)),
          brightness: magmaBrightness,
          alpha: 1.0
        )
        particles.mainEmitter.color = .evolving(
          start: .single(magmaStart),
          end: .single(.red.withAlphaComponent(0)))
      }
      // Speed affects motion, not audio analysis or the 18-second journey timer.
      particles.speed = motionRate.velocity(particles.speed)
      particles.speed = min(max(particles.speed, 0.05), 8.0)
      particles.mainEmitter.acceleration *= motionRate.multiplier * motionRate.multiplier
      particles.mainEmitter.angularSpeed *= motionRate.multiplier
      particles.mainEmitter.lifeSpan /= Double(sqrt(motionRate.multiplier))
      particles.mainEmitter.size *= model.particleSize
      particles.mainEmitter.sizeVariation = (0.001 + activity * 0.011) * model.particleSize
      let birthRate = ParticleBudget.birthRate(
        requested: particles.mainEmitter.birthRate, lifeSpan: particles.mainEmitter.lifeSpan)

      if orbitEmittersActive {
        entity.position = currentPos
        entity.orientation = simd_quatf(
          angle: time * 0.25 + phase, axis: normalize(SIMD3<Float>(1, 0.5, 0.3)))
        particles.mainEmitter.birthRate = birthRate * (1 - frontWeight)
        entity.components.set(particles)
      }

      if stageEmittersActive {
        let line = MirrorLineMode().stagePosition(index: index, time: time, bass: envelope.x)
        let grid = MirrorPlaneMode().stagePosition(index: index, time: time, bass: envelope.x)
        stage.position +=
          (line * (1 - planeWeight) + grid * planeWeight - stage.position) * (1 - exp(-dt * 4))
        particles.mainEmitter.birthRate = birthRate * stageWeight
        particles.birthDirection = .local
        let side: Float = stage.position.x < 0 ? -1 : 1
        particles.emissionDirection = [side * 0.15, 1, -0.1]
        particles.mainEmitter.spreadingAngle = 0.15
        // Match the color of each mirrored pair with beat palette rotation and high frequency sizzle.
        let pair = activeMode == .grid ? min(index % 4, 3 - index % 4) : min(index, 11 - index)
        let (stageStart, stageEnd) = reactiveEmitterColors(
          baseHue: Float(pair) * 0.12,
          bands: envelope,
          highFrequency: useFlux ? (highEnergy * 0.3 + highFlux * 0.7) : highEnergy,
          hueOffset: beatPulse.paletteHue,
          beatPulse: beatPulseIntensity,
          activity: activity
        )
        particles.mainEmitter.color = .evolving(
          start: .single(stageStart),
          end: .single(stageEnd))
        stage.components.set(particles)
      }
    }
  }
}
