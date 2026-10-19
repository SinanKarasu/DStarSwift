//
//  ContentView.swift
//  DStarSwift
//
//  Created by Sinan Karasu on 2/12/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var hud: DStarHUDState
    @EnvironmentObject private var net: NetSession

#if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isImmersiveActive = false
    @State private var immersiveStatus = "Windowed"
#endif

    var body: some View {
        ZStack {
            DStarMetalView(hud: hud)
                .ignoresSafeArea()

            DStarLegacyHUD(hud: hud)
                .allowsHitTesting(false)

            VStack(alignment: .trailing, spacing: 10) {
                statusBar
#if os(visionOS)
                HStack(spacing: 8) {
                    Image(systemName: "sun.min")
                    Slider(value: $hud.ambientLight, in: 0...1)
                        .frame(width: 160)
                    Text("\(Int(hud.ambientLight * 100))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
                .font(.caption)
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())

                Button(isImmersiveActive ? "Exit Immersive" : "Enter Immersive") {
                    Task {
                        await toggleImmersiveSpace()
                    }
                }
                .buttonStyle(.borderedProminent)

                Text(immersiveStatus)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
#endif

                HStack(spacing: 8) {
                    Button(net.isRunning ? "Stop Bonjour" : "Start Bonjour") {
                        if net.isRunning { net.stop() } else { net.start() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Spawn Robot") {
                        hud.commandSpawnRobot()
                    }
                    .buttonStyle(.bordered)
                }

#if os(macOS)
                Button("Visit Cylinder") { hud.onCommand?(.visitHabitat) }
                    .buttonStyle(.bordered)
#endif

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .overlay(alignment: .bottomTrailing) {
            DStarNavigationGlobe(hud: hud).padding()
        }
        .animation(.easeInOut(duration: 0.15), value: hud.showHelp)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            badge("●", color: hud.freezeFrame ? .yellow : .green,
                  label: hud.freezeFrame ? "paused" : "running")
            badge(hud.speedLabel, color: .white)
            if hud.autoPilot { badge("autopilot", color: .cyan) }
            if hud.radarOn { badge("radar", color: .green) }
            if hud.mouseControl { badge("mouse", color: .orange) }
            badge("missiles \(hud.armedMissiles)/\(hud.missilesRemaining)", color: .white)
            if net.isRunning {
                badge("net • \(net.peers.count) peer\(net.peers.count == 1 ? "" : "s")",
                      color: net.peers.isEmpty ? .yellow : .green)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private func badge(_ text: String, color: Color, label: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(text).foregroundStyle(color)
            if let label { Text(label).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

#if os(visionOS)
    @MainActor
    private func toggleImmersiveSpace() async {
        if isImmersiveActive {
            hud.onCommand?(.setGlobeSteering(.zero))
            await dismissImmersiveSpace()
            isImmersiveActive = false
            immersiveStatus = "Windowed"
            return
        }

        switch await openImmersiveSpace(id: DStarImmersiveSpace.id) {
        case .opened:
            isImmersiveActive = true
            immersiveStatus = "Immersive Active"
        case .userCancelled:
            isImmersiveActive = false
            immersiveStatus = "Immersive Cancelled"
        case .error:
            isImmersiveActive = false
            immersiveStatus = "Immersive Error"
        @unknown default:
            isImmersiveActive = false
            immersiveStatus = "Immersive Unknown State"
        }
    }
#endif
}

#Preview {
    ContentView()
        .environmentObject(DStarHUDState())
        .environmentObject(NetSession())
}
