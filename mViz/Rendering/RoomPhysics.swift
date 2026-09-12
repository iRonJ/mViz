import RealityKit
import SwiftUI
import UIKit

extension ParticleField {
  func stopRoom(model: VisualizerModel) {
    environment.stop()
    model.roomReady = false
    for particle in roomParticles { particle.entity.isEnabled = false }
  }

  func updateRoom(dt: Float, weight: Float, model: VisualizerModel) {
    surfacesAvailable = !environment.meshes.isEmpty
    var anyActive = false
    for particle in roomParticles {
      if particle.entity.isEnabled {
        anyActive = true
        break
      }
    }
    if anyActive {
      let envDist = simd_distance(envelope, lastRoomEnvelope)
      let updateColors = envDist > 0.03 || roomMaterials.isEmpty
      if updateColors {
        lastRoomEnvelope = envelope
        if roomMaterials.count != 8 {
          roomMaterials = (0..<8).map { _ in UnlitMaterial(color: .white) }
        }
        for b in 0..<8 {
          let hsv = reactiveColor(bands: envelope, offset: Float(b) * 0.025 + beatPulse.paletteHue)
          let color = UIColor(
            hue: CGFloat(hsv.x), saturation: CGFloat(hsv.y), brightness: CGFloat(hsv.z), alpha: 1)
          roomMaterials[b] = UnlitMaterial(color: color)
        }
      }
      for index in roomParticles.indices where roomParticles[index].entity.isEnabled {
        roomParticles[index].age += dt
        let age = roomParticles[index].age
        let particle = roomParticles[index].entity
        if particle.scale.x != model.particleSize {
          particle.scale = SIMD3(repeating: model.particleSize)
        }
        if age > 5 || particle.position.y < -3 {
          particle.isEnabled = false
        } else {
          if updateColors {
            particle.model?.materials = [roomMaterials[index % 8]]
          }
          if age > 4.5 {
            particle.components.set(OpacityComponent(opacity: (5 - age) * 2))
          }
        }
      }
    }
    guard model.roomEnabled, model.roomReady, surfacesAvailable, weight > 0.05 else {
      spawnBudget = 0
      return
    }
    let bassPunch = pow(envelope.x, 1.25)
    spawnBudget = min(4, spawnBudget + dt * (12 + bassPunch * 45) * model.intensity * weight)
    while spawnBudget >= 1 {
      spawnBudget -= 1
      guard let index = roomParticles.firstIndex(where: { !$0.entity.isEnabled }) else { break }
      let particle = roomParticles[index].entity
      let angle = time * 1.4 + Float(index) * 2.39996
      particle.scale = SIMD3(repeating: model.particleSize)
      particle.position = [cos(angle) * 1.1, 1.8 + envelope.x * 0.3, sin(angle) * 1.1]
      particle.components.set(OpacityComponent(opacity: 1))
      if roomMaterials.count == 8 {
        particle.model?.materials = [roomMaterials[index % 8]]
      }
      particle.components.set(
        PhysicsMotionComponent(
          linearVelocity: [
            cos(angle) * (0.8 + bassPunch * 0.6), 0.6 + bassPunch * 2.2,
            sin(angle) * (0.8 + bassPunch * 0.6),
          ]
            * MotionRate(model.motionSpeed).multiplier))
      roomParticles[index].age = 0
      particle.isEnabled = true
    }
  }

}
