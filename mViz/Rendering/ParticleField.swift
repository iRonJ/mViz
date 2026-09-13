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
  var stageEmitterSlots: [[Entity]] = []
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
  var emitterSlots: [[Entity]] = []
  var time: Float = 0
  var journeyTime: Float = 0
  var shapeTime: Float = 0
  private var macroTracker = SpectralFluxFollower<SIMD3<Float>>()
  private var geq10Tracker = SpectralFluxFollower<SIMD16<Float>>()
  private var linearBassEnvelope: Float = 0
  var envelope: SIMD3<Float> { macroTracker.envelope }
  var fluxEnvelope: SIMD3<Float> { macroTracker.flux }
  var geq10Envelope: SIMD16<Float> { geq10Tracker.envelope }
  var geq10FluxEnvelope: SIMD16<Float> { geq10Tracker.flux }
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
  private let stageLine: any StagePositionable = MirrorLineMode()
  private let stageGrid: any StagePositionable = MirrorPlaneMode()

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
      entity.name = "Orbit \(index)"
      entity.position = blend.position(phase: Float(index) / 12 * 2 * .pi, time: 0, bass: 0)
      root.addChild(entity)
      emitters.append(entity)

      let stage = Entity()
      stage.name = "Stage \(index)"
      stage.position = stageLine.stagePosition(index: index, time: 0, bass: 0)
      stageAnchor.addChild(stage)
      stageEmitters.append(stage)

      var orbitChildren: [Entity] = []
      var stageChildren: [Entity] = []

      for slot in 0..<3 {
        let child = Entity()
        child.name = "Orbit \(index) Slot \(slot)"
        var particles = ParticleEmitterComponent()
        particles.emitterShape = .sphere
        particles.emitterShapeSize = EmitterForm.sphere.dimensions
        particles.birthLocation = .surface
        particles.particlesInheritTransform = false
        particles.mainEmitter.blendMode = .additive
        particles.mainEmitter.birthRate = 33
        particles.mainEmitter.lifeSpan = slot == 0 ? 3.0 : (slot == 1 ? 2.5 : 1.7)
        particles.mainEmitter.size = slot == 0 ? 0.024 : (slot == 1 ? 0.018 : 0.012)
        particles.mainEmitter.sizeVariation = 0.008
        particles.mainEmitter.color = .evolving(start: .single(.cyan), end: .single(.purple))
        particles.speed = slot == 0 ? 0.12 : (slot == 1 ? 0.20 : 0.28)
        child.components.set(particles)
        entity.addChild(child)
        orbitChildren.append(child)

        let stageChild = Entity()
        stageChild.name = "Stage \(index) Slot \(slot)"
        particles.mainEmitter.birthRate = 0
        stageChild.components.set(particles)
        stage.addChild(stageChild)
        stageChildren.append(stageChild)
      }
      emitterSlots.append(orbitChildren)
      stageEmitterSlots.append(stageChildren)
    }
  }

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
    macroTracker.update(signal: signal, dt: dt, attackRates: attackRates, decayRates: decayRates)
    model.geqLevels = macroTracker.envelope
    model.macroFlux = macroTracker.flux

    let raw10 = model.bands10 * model.sensitivity * 8
    var sig10 = SIMD16<Float>.zero
    for i in 0..<10 {
      sig10[i] = AudioLevelCurve.map(raw10[i], logarithmic: model.logarithmicLevels)
    }
    let geq10Attack = SIMD16<Float>(50, 50, 50, 55, 55, 55, 55, 70, 70, 70, 0, 0, 0, 0, 0, 0)
    let geq10Decay = SIMD16<Float>(12, 12, 12, 16, 16, 16, 16, 24, 24, 24, 0, 0, 0, 0, 0, 0)
    geq10Tracker.update(signal: sig10, dt: dt, attackRates: geq10Attack, decayRates: geq10Decay)
    model.geq10Levels = geq10Tracker.envelope
    model.geq10Flux = geq10Tracker.flux
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
        for slots in stageEmitterSlots {
          for stageChild in slots {
            guard var p = stageChild.components[ParticleEmitterComponent.self] else { continue }
            p.mainEmitter.birthRate = 0
            stageChild.components.set(p)
          }
        }
        stageEmittersActive = false
      }
    } else {
      stageEmittersActive = true
    }

    if frontWeight > 0.999 {
      if orbitEmittersActive {
        for slots in emitterSlots {
          for orbitChild in slots {
            guard var p = orbitChild.components[ParticleEmitterComponent.self] else { continue }
            p.mainEmitter.birthRate = 0
            orbitChild.components.set(p)
          }
        }
        orbitEmittersActive = false
      }
    } else {
      orbitEmittersActive = true
    }

    let blendedDynamics = blend.dynamics(bass: envelope.x)

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

      let currentPos = blend.position(phase: phase, time: time, bass: envelope.x)

      if orbitEmittersActive {
        entity.position = currentPos
        entity.orientation = simd_quatf(
          angle: time * 0.25 + phase, axis: normalize(SIMD3<Float>(1, 0.5, 0.3)))
      }

      if stageEmittersActive {
        let line = stageLine.stagePosition(index: index, time: time, bass: envelope.x)
        let grid = stageGrid.stagePosition(index: index, time: time, bass: envelope.x)
        stage.position +=
          (line * (1 - planeWeight) + grid * planeWeight - stage.position) * (1 - exp(-dt * 4))
      }

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
      let aurora = blend[.aurora]
      let vortex = blend[.vortex]
      let bandEnergy: Float =
        index < 10 ? geq10Envelope[index] : (index == 10 ? envelope.x : envelope.z)

      let horizontalDist = sqrt(
        currentPos.x * currentPos.x + currentPos.z * currentPos.z)
      let angle = horizontalDist > 0.001 ? atan2(currentPos.z, currentPos.x) : phase
      let dy = currentPos.y - 1.5
      let verticalBias: Float = dy > 1.0 ? -0.3 : (dy < -0.8 ? 0.4 : 0)
      let rawDir = SIMD3<Float>(
        cos(angle + .pi / 2),
        aurora * 0.8 + sin(time + phase) * 0.3 + verticalBias,
        sin(angle + .pi / 2)
      )
      let rawDirLen = length(rawDir)
      let defaultDir = rawDirLen > 0.001 ? rawDir / rawDirLen : SIMD3<Float>(0, 1, 0)
      let blendedDir: SIMD3<Float>
      if blendedDynamics.directionWeight > 0.001 {
        let mixed = defaultDir * (1 - blendedDynamics.directionWeight) + blendedDynamics.direction
        let mLen = length(mixed)
        blendedDir = mLen > 0.001 ? mixed / mLen : defaultDir
      } else {
        blendedDir = defaultDir
      }

      for slot in 0..<3 {
        let orbitChild = emitterSlots[index][slot]
        let stageChild = stageEmitterSlots[index][slot]
        guard var particles = orbitChild.components[ParticleEmitterComponent.self] else { continue }

        particles.emitterShape = currentForm.shape
        particles.torusInnerRadius = 0.7
        particles.birthDirection = .world
        particles.emissionDirection = blendedDir
        particles.mainEmitter.acceleration = .zero
        particles.mainEmitter.acceleration.y += blendedDynamics.gravity

        // 1. Frequency-specific density (reduced by 1/3 for each sub-emitter)
        let slotFloor = (1.0 + activity * 7.0) / 3.0
        let roomReduction = 1 - blend[.room] * (surfacesAvailable ? 0.85 : 0)
        let requestedBirthRate: Float

        // 2. Frequency-specific particle sizing & speed
        let dynamicSize: Float
        let slotSpeed: Float
        let slotLifespan: Double
        let slotNoise: Float
        let slotSpread: Float
        let slotHueOffset: Float
        var slotStretch: Float = 1.0

        switch slot {
        case 0:  // Bass / Low-frequency slot (~40-250 Hz)
          let bassBurst =
            (bassPunch * 280 + lowBandBoost * 180 + beatPulseIntensity * 120)
            * (index < 3 ? 1.25 : 1.0)
          requestedBirthRate =
            (slotFloor + bassBurst) * model.intensity * roomReduction
            * blendedDynamics.birthMultiplier
          let baseSize: Float = 0.0028 + activity * 0.0055
          dynamicSize =
            (baseSize + bassPunch * 0.046 + beatPulseIntensity * 0.025 + lowBandBoost * 0.022)
            * activeDynamics.sizeScale * 1.35
          slotSpeed = 0.05 + bassPunch * 0.40 + blendedDynamics.speedBoost * 0.6
          slotLifespan = activeDynamics.lifeSpan ?? Double(3.0 + aurora * 1.0)
          slotNoise = 0.02 + bassPunch * 0.04
          slotSpread = 0.20 + blendedDynamics.spreadBoost * 0.6
          slotHueOffset = -0.04
          particles.emitterShapeSize =
            currentForm.dimensions * shapeScale * (0.90 + bassPunch * 0.85)

        case 1:  // Mid / Melodic body slot (~250-2500 Hz)
          let midBurst =
            (midDensity * 360 + midBandBoost * 160 + bandEnergy * 60)
            * (index >= 3 && index <= 6 ? 1.25 : 1.0)
          requestedBirthRate =
            (slotFloor + midBurst) * model.intensity * roomReduction
            * blendedDynamics.birthMultiplier
          let baseSize: Float = 0.0016 + activity * 0.0040
          dynamicSize =
            (baseSize + midDensity * 0.024 + midBandBoost * 0.015) * activeDynamics.sizeScale
          slotSpeed = 0.07 + midSpeed * 0.95 + vortex * 0.25 + blendedDynamics.speedBoost
          slotLifespan = activeDynamics.lifeSpan ?? Double(2.5 + aurora * 0.8)
          slotNoise = 0.04 + midDensity * 0.10
          slotSpread = 0.28 + blendedDynamics.spreadBoost
          slotHueOffset = 0.0
          particles.emitterShapeSize =
            currentForm.dimensions * shapeScale * (0.80 + midDensity * 0.50)

        default:  // High / Treble sizzle slot (~2500-16000 Hz)
          let trebleBurst =
            (trebleSizzle * 380 + highEnergy * 140 + highFlux * 180)
            * (index >= 7 && index <= 9 ? 1.25 : 1.0)
          requestedBirthRate =
            (slotFloor + trebleBurst) * model.intensity * roomReduction
            * blendedDynamics.birthMultiplier
          let baseSize: Float = 0.0010 + activity * 0.0028
          dynamicSize =
            (baseSize + trebleSizzle * 0.016 + highEnergy * 0.010) * activeDynamics.sizeScale
            * 0.75
          slotSpeed = 0.09 + trebleSizzle * 1.40 + blendedDynamics.speedBoost * 1.2
          slotLifespan = (activeDynamics.lifeSpan ?? Double(1.8 + aurora * 0.5)) * 0.75
          slotNoise = 0.06 + trebleSizzle * 0.45
          slotSpread = 0.38 + trebleSizzle * 0.30 + blendedDynamics.spreadBoost * 1.2
          slotHueOffset = 0.06
          slotStretch = (activeDynamics.stretch ?? 1.0) * (1.6 + trebleSizzle * 2.8)
          particles.emitterShapeSize =
            currentForm.dimensions * shapeScale * (0.70 + trebleSizzle * 0.40)
        }

        particles.speed = slotSpeed
        particles.mainEmitter.size = dynamicSize
        particles.mainEmitter.lifeSpan = slotLifespan

        // 3. Rotating particle style & texture
        let slotStyle = styleFor(
          slot: slot, nodeIndex: index, shapeTime: shapeTime, selectedStyle: model.particleStyle)
        applyStyle(slotStyle, to: &particles, slot: slot)

        particles.mainEmitter.noiseStrength = slotNoise
        particles.mainEmitter.noiseAnimationSpeed =
          motionRate.multiplier * (1.0 + (slot == 2 ? trebleSizzle * 3.5 : 0.5))
        particles.mainEmitter.spreadingAngle = slotSpread
        if let stretch = activeDynamics.stretch {
          particles.mainEmitter.stretchFactor = stretch * slotStretch
        } else {
          particles.mainEmitter.stretchFactor *= slotStretch
        }

        // 4. Color tuning per slot
        let baseEmitterHue = Float(index) / 12.0 + aurora * 0.15 + slotHueOffset
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

        if let custom = activeMode.definition.customEmitterColor(
          index: index,
          envelope: envelope,
          trebleSizzle: trebleSizzle,
          paletteHue: beatPulse.paletteHue,
          beatIntensity: beatPulseIntensity,
          activity: activity
        ) {
          particles.mainEmitter.color = .evolving(
            start: .single(custom.start),
            end: .single(custom.end))
        }

        if model.shape == .evolving, let form = activeDynamics.form {
          particles.emitterShape = form == .plane ? .plane : .cone
          particles.emitterShapeSize = form == .plane ? [1.2, 0.02, 1.2] : [0.3, 0.3, 0.3]
        }

        // Motion rate adjustments
        particles.speed = motionRate.velocity(particles.speed)
        particles.speed = min(max(particles.speed, 0.05), 8.0)
        particles.mainEmitter.acceleration *= motionRate.multiplier * motionRate.multiplier
        particles.mainEmitter.angularSpeed *= motionRate.multiplier
        particles.mainEmitter.lifeSpan /= Double(sqrt(motionRate.multiplier))
        particles.mainEmitter.size *= model.particleSize
        particles.mainEmitter.sizeVariation = (0.001 + activity * 0.008) * model.particleSize

        let birthRate = ParticleBudget.birthRate(
          requested: requestedBirthRate, lifeSpan: particles.mainEmitter.lifeSpan)

        if orbitEmittersActive {
          particles.mainEmitter.birthRate = birthRate * (1 - frontWeight)
          orbitChild.components.set(particles)
        }

        if stageEmittersActive {
          particles.mainEmitter.birthRate = birthRate * stageWeight
          particles.birthDirection = .local
          let side: Float = stage.position.x < 0 ? -1 : 1
          particles.emissionDirection = [side * 0.15, 1, -0.1]
          particles.mainEmitter.spreadingAngle = slot == 2 ? 0.28 : 0.15
          let pair = activeMode == .grid ? min(index % 4, 3 - index % 4) : min(index, 11 - index)
          let (stageStart, stageEnd) = reactiveEmitterColors(
            baseHue: Float(pair) * 0.12 + slotHueOffset,
            bands: envelope,
            highFrequency: useFlux ? (highEnergy * 0.3 + highFlux * 0.7) : highEnergy,
            hueOffset: beatPulse.paletteHue,
            beatPulse: beatPulseIntensity,
            activity: activity
          )
          particles.mainEmitter.color = .evolving(
            start: .single(stageStart),
            end: .single(stageEnd))
          stageChild.components.set(particles)
        }
      }
    }
  }
}
