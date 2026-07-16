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
        ZStack(alignment: .topLeading) {
            DStarMetalView(hud: hud)
                .ignoresSafeArea()

            statusBar
                .padding(12)

            if hud.showHelp {
                helpOverlay
                    .transition(.opacity)
            }

#if os(visionOS)
            VStack(alignment: .trailing, spacing: 8) {
                Spacer()
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
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .trailing)
#endif
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

    private var helpOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DStar — Key Bindings")
                .font(.headline)
                .padding(.bottom, 4)
            Group {
                bindingRow("0 / 1 / 2", "stop / half / full speed")
                bindingRow("+ / -", "speed up / slow down")
                bindingRow("← ↑ → ↓", "steer")
                bindingRow("mouse", "aim   ·   left-click toggles mouse-fly")
                bindingRow("right mouse", "fire laser")
                bindingRow("a / A", "autopilot  /  autopilot + autofire")
                bindingRow("r", "toggle radar")
                bindingRow("Tab", "next radar target")
                bindingRow("q / F2", "arm missile")
                bindingRow("w / F3", "launch missile")
                bindingRow("f / Esc", "freeze frame")
                bindingRow("h / F1 / ?", "toggle this help")
                bindingRow("l", "toggle ringworld trim lines")
                bindingRow("p", "print location (debug)")
                bindingRow("b", "spawn local AI robot")
            }
            Divider().padding(.vertical, 4)
            Group {
                bindingRow("⌘Q", "quit")
                bindingRow("⌘?", "toggle help")
                bindingRow("⌘⇧H", "start / stop multiplayer (Bonjour)")
                bindingRow("⌘B", "spawn AI robot")
                bindingRow("⌘,", "preferences (coming soon)")
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 420)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func bindingRow(_ key: String, _ desc: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.primary)
            Text(desc)
                .foregroundStyle(.secondary)
        }
    }

#if os(visionOS)
    @MainActor
    private func toggleImmersiveSpace() async {
        if isImmersiveActive {
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
