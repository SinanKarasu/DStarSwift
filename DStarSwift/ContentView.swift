//
//  ContentView.swift
//  DStarSwift
//
//  Created by Sinan Karasu on 2/12/26.
//

import SwiftUI

struct ContentView: View {
#if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isImmersiveActive = false
    @State private var immersiveStatus = "Windowed"
#endif

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DStarMetalView()
                .ignoresSafeArea()
#if os(visionOS)
            VStack(alignment: .trailing, spacing: 8) {
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
#endif
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
}
