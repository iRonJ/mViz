//
//  ImmersiveView.swift
//  mViz
//
//  Created by Ron Jailall on 3/8/24.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    var body: some View {
//        ImmersiveSpace(id: "disco"){
            RealityView { content in
                // Add the initial RealityKit content
                if let scene = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                    content.add(scene)
                }
                let model = ModelEntity()
                model.components.set(particleSystem())
                let rotationAngle: Float = 1.4
                //model.transform.rotation *= simd_quatf(angle: rotationAngle, axis: [1, 0, 1])
                model.transform.translation = SIMD3<Float>(0.0, -1.0, 0)
                content.add(model)
                
            }
       // }
    }
}
func particleSystem() -> ParticleEmitterComponent {
       var particles = ParticleEmitterComponent()
       particles.emitterShape = .plane
       particles.emitterShapeSize = [1,1,1] * 1
       particles.mainEmitter.birthRate = 2000
       particles.mainEmitter.size = 0.05
       particles.mainEmitter.lifeSpan = 3

       let angle: Float = 4.4 // Fill in the desired value
       let angleVariation: Float = 1.4 // Fill in the desired value
       let angularSpeed: Float = 2.4 // Fill in the desired value
       let angularSpeedVariation: Float = 3.0 // Fill in the desired value
    particles.emissionDirection = SIMD3<Float>(0.0, 1.0, 0.0)
       particles.mainEmitter.angle = angle
       particles.mainEmitter.angleVariation = angleVariation
       particles.mainEmitter.angularSpeed = angularSpeed
       particles.mainEmitter.angularSpeedVariation = angularSpeedVariation
       particles.mainEmitter.color = .evolving(start: .single(.white), end: .single(.red))

       return particles
   }
#Preview {
    ImmersiveView()
        .previewLayout(.sizeThatFits)
}
