import RealityKit
import UIKit

enum ParticleStyle: String, CaseIterable, Identifiable {
  case evolving = "Evolving"
  case glow = "Glow"
  case sparks = "Sparks"
  case rings = "Halo rings"
  case flakes = "Snowflakes"
  var id: Self { self }
}

enum EmitterForm: String, CaseIterable, Identifiable {
  case evolving = "Evolving"
  case sphere = "Spheres"
  case torus = "Rings"
  case plane = "Ribbons"
  case cone = "Cones"
  case box = "Cubes"
  var id: Self { self }

  var shape: ParticleEmitterComponent.EmitterShape {
    switch self {
    case .evolving, .sphere: .sphere
    case .torus: .torus
    case .plane: .plane
    case .cone: .cone
    case .box: .box
    }
  }

  var dimensions: SIMD3<Float> {
    switch self {
    case .evolving, .sphere: [0.4, 0.4, 0.4]
    case .torus: [0.65, 0.65, 0.65]
    case .plane: [0.9, 0.12, 0.25]
    case .cone: [0.5, 0.8, 0.5]
    case .box: [0.45, 0.45, 0.45]
    }
  }
}

extension ParticleField {
  func makeTexture(_ style: ParticleStyle) -> TextureResource? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image {
      context in
      UIColor.white.setStroke()
      UIColor.white.setFill()
      let path = UIBezierPath()
      switch style {
      case .rings:
        path.append(UIBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 44, height: 44)))
        path.lineWidth = 4
        path.stroke()
      case .flakes:
        for i in 0..<6 {
          let angle = CGFloat(i) * .pi / 3
          let dx = cos(angle)
          let dy = sin(angle)
          path.move(to: CGPoint(x: 32, y: 32))
          path.addLine(to: CGPoint(x: 32 + dx * 25, y: 32 + dy * 25))
          for side: CGFloat in [-1, 1] {
            path.move(to: CGPoint(x: 32 + dx * 16, y: 32 + dy * 16))
            path.addLine(
              to: CGPoint(x: 32 + dx * 10 - dy * side * 7, y: 32 + dy * 10 + dx * side * 7))
          }
        }
        path.lineWidth = 2.5
        path.stroke()
      case .sparks:
        path.move(to: CGPoint(x: 32, y: 2))
        path.addLine(to: CGPoint(x: 38, y: 27))
        path.addLine(to: CGPoint(x: 62, y: 32))
        path.addLine(to: CGPoint(x: 38, y: 37))
        path.addLine(to: CGPoint(x: 32, y: 62))
        path.addLine(to: CGPoint(x: 26, y: 37))
        path.addLine(to: CGPoint(x: 2, y: 32))
        path.addLine(to: CGPoint(x: 26, y: 27))
        path.close()
        path.fill()
      case .evolving, .glow:
        let colors =
          [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(
          colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
        {
          context.cgContext.drawRadialGradient(
            gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
            endCenter: CGPoint(x: 32, y: 32), endRadius: 30, options: [])
        }
      }
    }
    guard let cgImage = image.cgImage else { return nil }
    return try? TextureResource(image: cgImage, options: .init(semantic: .color))
  }

  static let evolvingForms: [EmitterForm] = [.sphere, .torus, .plane, .cone, .box]
  static let evolvingStyles: [ParticleStyle] = [.glow, .sparks, .rings, .flakes]

  func styleFor(slot: Int, nodeIndex: Int, shapeTime: Float, selectedStyle: ParticleStyle) -> ParticleStyle {
    guard selectedStyle == .evolving else { return selectedStyle }
    let cycle = Int(shapeTime / 10)
    let styleIndex = (cycle + slot + nodeIndex) % Self.evolvingStyles.count
    return Self.evolvingStyles[styleIndex]
  }

  func applyStyle(_ style: ParticleStyle, to particles: inout ParticleEmitterComponent, slot: Int = 1) {
    if let tex = textures[style] {
      particles.mainEmitter.image = tex
    }
    particles.mainEmitter.stretchFactor = style == .sparks ? 3.5 : 1
    particles.mainEmitter.opacityCurve = style == .sparks ? .linearFadeOut : .gradualFadeInOut
    particles.mainEmitter.sizeMultiplierAtEndOfLifespan = style == .rings ? 2.6 : 0.25
    let baseAngularSpeed: Float = slot == 0 ? 0.35 : (slot == 1 ? 0.85 : 1.9)
    particles.mainEmitter.angularSpeed = style == .flakes ? baseAngularSpeed * 1.4 : baseAngularSpeed
    particles.mainEmitter.angularSpeedVariation = particles.mainEmitter.angularSpeed * 0.75
    particles.mainEmitter.noiseStrength = style == .flakes ? 0.18 : 0.03
    particles.mainEmitter.noiseScale = 0.5
    if style == .rings || style == .flakes { particles.mainEmitter.size *= 2.2 }
    if style == .sparks { particles.mainEmitter.lifeSpan *= 0.8 }
  }
}
