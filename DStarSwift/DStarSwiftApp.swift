//
//  DStarSwiftApp.swift
//  DStarSwift
//
//  Created by Sinan Karasu on 2/12/26.
//

import SwiftUI

@main
struct DStarSwiftApp: App {
    @StateObject private var hud = DStarHUDState()

#if os(visionOS)
    @State private var immersionStyle: ImmersionStyle = .mixed
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(hud)
        }
#if os(macOS)
        .commands {
            // No documents to create — drop the default "New" item.
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Game") {
                Button(hud.freezeFrame ? "Resume" : "Pause") {
                    hud.commandToggleFreeze()
                }
                .keyboardShortcut(".", modifiers: [.command])

                Button(hud.autoPilot ? "Autopilot Off" : "Autopilot On") {
                    hud.commandToggleAutopilot()
                }
                .keyboardShortcut("a", modifiers: [.command])

                Button(hud.radarOn ? "Radar Off" : "Radar On") {
                    hud.commandToggleRadar()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Stop")        { hud.commandStop() }
                    .keyboardShortcut("0", modifiers: [.command])
                Button("Half Speed")  { hud.commandHalfSpeed() }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Full Speed")  { hud.commandFullSpeed() }
                    .keyboardShortcut("2", modifiers: [.command])

                Divider()

                Button("Arm Missile")    { hud.commandArmMissile() }
                    .keyboardShortcut("m", modifiers: [.command])
                Button("Launch Missile") { hud.commandLaunchMissile() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button(hud.showHelp ? "Hide Key Bindings" : "Show Key Bindings") {
                    hud.commandToggleHelp()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
        }
#endif

#if os(visionOS)
        ImmersiveSpace(id: DStarImmersiveSpace.id) {
            DStarImmersiveView()
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full)
#endif
    }
}
