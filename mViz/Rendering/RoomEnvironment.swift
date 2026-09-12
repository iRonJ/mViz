import ARKit
import RealityKit
import UIKit

/// One reconstruction session supplies both physical surfaces and beat-light overlays.
@MainActor
final class RoomEnvironment {
  let root = Entity()
  private var session: ARKitSession?
  private var generation = 0
  private(set) var meshes: [UUID: ModelEntity] = [:]
  private var lastOpacity: Float = -1
  private var lastColor: UIColor?
  private var sharedMaterial = UnlitMaterial(color: .white)

  func stop() {
    generation += 1
    session?.stop()
    session = nil
    lastOpacity = -1
    lastColor = nil
    for mesh in meshes.values { mesh.removeFromParent() }
    meshes.removeAll()
  }

  func run(enabled: Bool, model: VisualizerModel) async {
    stop()
    model.roomReady = false
    guard enabled else { return }
    guard SceneReconstructionProvider.isSupported else {
      model.roomStatus = "Room reconstruction is unavailable on this device."
      return
    }
    let request = generation
    let session = ARKitSession()
    self.session = session
    let provider = SceneReconstructionProvider()
    model.roomStatus = "Requesting room access…"
    do {
      try await session.run([provider])
      guard request == generation, !Task.isCancelled else { return }
      model.roomReady = true
      model.roomStatus = "Scanning room surfaces • look around."
      for await update in provider.anchorUpdates {
        guard request == generation, !Task.isCancelled else { return }
        let anchor = update.anchor
        if update.event == .removed {
          meshes.removeValue(forKey: anchor.id)?.removeFromParent()
          continue
        }
        do {
          let shape = try await ShapeResource.generateStaticMesh(from: anchor)
          let mesh = try await MeshResource(from: anchor)
          guard request == generation, !Task.isCancelled else { return }
          let entity = meshes[anchor.id] ?? ModelEntity()
          let previousMaterials = entity.model?.materials ?? [UnlitMaterial(color: .white)]
          entity.model = ModelComponent(mesh: mesh, materials: previousMaterials)
          entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
          entity.components.set(
            CollisionComponent(
              shapes: [shape], filter: CollisionFilter(group: .sceneUnderstanding, mask: .default)))
          entity.components.set(PhysicsBodyComponent(mode: .static))
          if meshes[anchor.id] == nil {
            entity.components.set(OpacityComponent(opacity: 0))
            root.addChild(entity)
            meshes[anchor.id] = entity
          }
          model.roomStatus = "Room surfaces ready • \(meshes.count) mesh sections"
        } catch {
          model.roomStatus = "A room surface couldn’t update. Continuing with detected surfaces."
        }
      }
    } catch {
      guard request == generation else { return }
      model.roomReady = false
      model.roomStatus =
        "Room sensing unavailable: \(error.localizedDescription). Check World Sensing permission."
    }
  }

  func illuminate(color: UIColor, opacity: Float) {
    guard !meshes.isEmpty else { return }
    if opacity <= 0.001 && lastOpacity <= 0.001 { return }
    let opacityChanged = abs(opacity - lastOpacity) > 0.005 || (opacity <= 0.001 && lastOpacity > 0.001)
    let colorChanged = color != lastColor
    guard opacityChanged || colorChanged else { return }

    if opacity > 0.001 && colorChanged {
      sharedMaterial = UnlitMaterial(color: color)
      lastColor = color
    }
    lastOpacity = opacity

    for mesh in meshes.values {
      if opacity > 0.001 && colorChanged {
        mesh.model?.materials = [sharedMaterial]
      }
      if opacityChanged {
        mesh.components.set(OpacityComponent(opacity: opacity))
      }
    }
  }
}
