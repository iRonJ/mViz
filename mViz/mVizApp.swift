//
//  mVizApp.swift
//  mViz
//
//  Created by Ron Jailall on 3/8/24.
//

import SwiftUI

@main
struct mVizApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }.windowStyle(.volumetric)

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
        }
    }
}
