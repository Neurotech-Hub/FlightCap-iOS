//
//  Theme.swift
//  FlightCap
//

import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.07, blue: 0.12)
    static let panel      = Color(red: 0.10, green: 0.13, blue: 0.20)
    static let motion     = Color(red: 0.35, green: 0.92, blue: 1.00)
    static let distance   = Color(red: 1.00, green: 0.42, blue: 0.65)
    static let dim        = Color.white.opacity(0.55)

    static let accentGradient = LinearGradient(
        colors: [motion, distance],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
