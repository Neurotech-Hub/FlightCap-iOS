//
//  FlightCapApp.swift
//  FlightCap
//
//  Created by Matt Gaidica on 5/20/26.
//

import SwiftUI

@main
struct FlightCapApp: App {
    @StateObject private var ble = BLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .preferredColorScheme(.dark)
        }
    }
}
