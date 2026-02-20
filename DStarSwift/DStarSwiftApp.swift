//
//  DStarSwiftApp.swift
//  DStarSwift
//
//  Created by Sinan Karasu on 2/12/26.
//

import SwiftUI

@main
struct DStarSwiftApp: App {
#if os(visionOS)
    @State private var immersionStyle: ImmersionStyle = .mixed
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
#if os(visionOS)
        ImmersiveSpace(id: DStarImmersiveSpace.id) {
            DStarImmersiveView()
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full)
#endif
    }
}
