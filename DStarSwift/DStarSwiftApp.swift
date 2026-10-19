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
    @StateObject private var net = NetSession()

#if os(visionOS)
    @State private var immersionStyle: ImmersionStyle = .full
#endif

    init() {
        // Wire HUD → NetSession once the renderer has a game state.
        // We can't do this in @StateObject initializer (instance not yet
        // bound), so we register inside `body` via a one-shot side effect.
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(hud)
                .environmentObject(net)
                .onAppear {
                    hud.onGameStateReady = { game in
                        net.attach(game: game)
                    }
                }
        }
#if os(macOS)
        .commands {
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

            CommandMenu("Multiplayer") {
                Button(net.isRunning ? "Stop Hosting" : "Start Hosting (Bonjour)") {
                    if net.isRunning { net.stop() } else { net.start() }
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Text("Local name: \(net.localName)")
                Text(net.peers.isEmpty ? "No peers"
                                       : "Peers: \(net.peers.joined(separator: ", "))")

                Divider()

                Button("Spawn Robot") { hud.commandSpawnRobot() }
                    .keyboardShortcut("b", modifiers: [.command])
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
                .environmentObject(hud)
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full)
#endif
    }
}
