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
  var geq10Envelope = SIMD16<Float>.zero
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
      model.shape == .evolving ? Self.evolvingForms[Int(shapeTime / 8) % Self.evolvingForms.count] : model.shape
    // Collapse the emission surface, change topology, then expand. Existing
    // particles keep their world-space trails throughout the transition.
    if desiredForm != currentForm {
      shapeScale = max(0.02, shapeScale - dt * 2)
      if shapeScale <= 0.02 { currentForm = desiredForm }
    } else {
      shapeScale = min(1, shapeScale + dt * 1.5)
    }

    let raw = model.bands * model.sensitivity * 8
    let signal = SIMD3<Float>(min(1, raw.x), min(1, raw.y), min(1, raw.z))
    for i in 0..<3 {
      let rate: Float = signal[i] > envelope[i] ? 18 : 4
      envelope[i] += (signal[i] - envelope[i]) * (1 - exp(-dt * rate))
    }
    model.geqLevels = envelope

    let raw10 = model.bands10 * model.sensitivity * 8
    for i in 0..<10 {
      let sig = min(1, max(0, raw10[i]))
      let rate: Float = sig > geq10Envelope[i] ? 18 : 4
      geq10Envelope[i] += (sig - geq10Envelope[i]) * (1 - exp(-dt * rate))
    }
    model.geq10Levels = geq10Envelope
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
      bass: envelope.x, dt: dt, pulseWeight: pulseWeight, strobeWeight: strobeWeight)
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
      levels: geq10Envelope, time: time, weight: blend[.flurry],
      intensity: model.intensity, speed: model.motionSpeed, reduceMotion: model.reduceMotion)
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
      blendedBirthMultiplier *= (1 + dynamics.birthBoost * weight)
    }

    updateRoom(dt: dt, weight: blend[.room], model: model)
    let activeDynamics = activeMode.definition.dynamics(bass: envelope.x)
    let planeWeight = stageWeight > 0.001 ? blend[.grid] / stageWeight : 0
    for index in 0..<12 {
      let entity = emitters[index]
      let stage = stageEmitters[index]
      let phase = Float(index) / 12 * 2 * .pi
      guard var particles = entity.components[ParticleEmitterComponent.self] else { continue }

      let currentPos = blend.position(phase: phase, time: time, bass: envelope.x)

      particles.emitterShape = currentForm.shape
      particles.emitterShapeSize = currentForm.dimensions * shapeScale * (1 + envelope.x * 0.5)
      particles.torusInnerRadius = 0.7
      let aurora = blend[.aurora]
      let vortex = blend[.vortex]
      let bandEnergy: Float =
        index < 10 ? geq10Envelope[index] : (index == 10 ? envelope.x : envelope.z)
      let baseBirthRate =
        (50 + bandEnergy * 240 + envelope.x * 60) * model.intensity
        * (1 - blend[.room] * (surfacesAvailable ? 0.85 : 0))
      particles.mainEmitter.lifeSpan = Double(2.5 + aurora * 0.8)
      particles.mainEmitter.size = 0.012 + bandEnergy * 0.022 + envelope.x * 0.008
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

      let hue = CGFloat(
        (Float(index) / 12 + time * 0.025 + aurora * 0.15).truncatingRemainder(dividingBy: 1))
      let color = UIColor(hue: hue, saturation: 0.75, brightness: 1, alpha: 1)
      let end = UIColor(
        hue: (hue + 0.18).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 0.7,
        alpha: 0)
      particles.mainEmitter.color = .evolving(start: .single(color), end: .single(end))
      particles.mainEmitter.acceleration = .zero
      particles.mainEmitter.spreadingAngle = 0.3

      // Reset base speed fresh every frame so it never compounds across frames
      particles.speed = 0.15 + envelope.y * 0.65 + vortex * 0.25
      particles.speed += blendedSpeedBoost
      particles.mainEmitter.acceleration.y += blendedGravity
      particles.mainEmitter.spreadingAngle += blendedSpreadBoost
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
      if let stretch = activeDynamics.stretch { particles.mainEmitter.stretchFactor = stretch }
      if let lifeSpan = activeDynamics.lifeSpan { particles.mainEmitter.lifeSpan = lifeSpan }
      particles.mainEmitter.size *= activeDynamics.sizeScale
      if activeMode == .volcano {
        particles.mainEmitter.color = .evolving(
          start: .single(
            UIColor(
              hue: CGFloat(0.03 + envelope.x * 0.12), saturation: 0.7, brightness: 1, alpha: 1)),
          end: .single(.red.withAlphaComponent(0)))
      }
      // Speed affects motion, not audio analysis or the 18-second journey timer.
      particles.speed = motionRate.velocity(particles.speed)
      particles.speed = min(max(particles.speed, 0.05), 8.0)
      particles.mainEmitter.acceleration *= motionRate.multiplier * motionRate.multiplier
      particles.mainEmitter.angularSpeed *= motionRate.multiplier
      particles.mainEmitter.noiseAnimationSpeed = motionRate.multiplier
      particles.mainEmitter.lifeSpan /= Double(sqrt(motionRate.multiplier))
      let birthRate = particles.mainEmitter.birthRate

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
        // Match the color of each mirrored pair as well as its motion.
        let pair = activeMode == .grid ? min(index % 4, 3 - index % 4) : min(index, 11 - index)
        let stageHue = CGFloat(
          (Float(pair) * 0.09 + time * 0.025).truncatingRemainder(dividingBy: 1))
        particles.mainEmitter.color = .evolving(
          start: .single(UIColor(hue: stageHue, saturation: 0.7, brightness: 1, alpha: 1)),
          end: .single(.clear))
        stage.components.set(particles)
      }
    }
  }
}
