//
//  ScanView.swift
//  FlightCap
//

import SwiftUI

struct ScanView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
                .padding(.bottom, 8)

            Text("FlightCap")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button(action: { ble.startScan() }) {
                HStack(spacing: 14) {
                    if isBusy {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                    }
                    Text(buttonLabel)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Theme.accentGradient)
                )
                .shadow(color: Theme.motion.opacity(0.35), radius: 18, x: 0, y: 8)
                .opacity(isBusy ? 0.85 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .padding(.horizontal, 24)

            Group {
                if let msg = ble.lastMessage {
                    Text(msg)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.dim)
                } else {
                    Text(" ")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isBusy: Bool {
        ble.state == .scanning || ble.state == .connecting
    }

    private var buttonLabel: String {
        switch ble.state {
        case .scanning:   return "Scanning…"
        case .connecting: return "Connecting…"
        default:          return "Scan for Cap"
        }
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        ScanView().environmentObject(BLEManager())
    }
    .preferredColorScheme(.dark)
}
