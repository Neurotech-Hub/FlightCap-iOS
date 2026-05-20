//
//  ContentView.swift
//  FlightCap
//
//  Created by Matt Gaidica on 5/20/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Group {
                switch ble.state {
                case .connected:
                    ConnectedView()
                default:
                    ScanView()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: ble.state)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BLEManager())
        .preferredColorScheme(.dark)
}
