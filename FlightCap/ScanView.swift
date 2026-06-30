//
//  ScanView.swift
//  FlightCap
//

import SwiftUI

struct ScanView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 16)
                .padding(.bottom, 12)

            scanButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            if let msg = ble.lastMessage {
                Text(msg)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 8)
            }

            capList
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)

            Text("FlightCap")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var scanButton: some View {
        Button(action: scanButtonAction) {
            HStack(spacing: 14) {
                if ble.state == .scanning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                }
                Text(scanButtonLabel)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.accentGradient)
            )
            .opacity(ble.state == .scanning ? 0.85 : 1.0)
            .shadow(color: Theme.motion.opacity(0.3), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var capList: some View {
        Group {
            if ble.discoveredCaps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(ble.discoveredCaps) { cap in
                            CapRow(cap: cap) {
                                ble.selectCap(cap)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(emptyStateMessage)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var scanButtonLabel: String {
        ble.state == .scanning ? "Stop Scanning" : "Scan for Caps"
    }

    private var emptyStateMessage: String {
        ble.state == .scanning
            ? "No caps heard yet…"
            : "Tap Scan for Caps to discover"
    }

    private func scanButtonAction() {
        if ble.state == .scanning {
            ble.stopScan()
        } else {
            ble.startDiscoveryScan()
        }
    }
}

private struct CapRow: View {
    let cap: DiscoveredCap
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cap.displayName)
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        Text("\(cap.rssi) dBm")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.dim)

                        Text(cap.lastSeen, style: .relative)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.dim)
                    }
                }

                Spacer()

                if cap.isPairMode {
                    Text("Pair")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.motion))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        ScanView().environmentObject(BLEManager())
    }
    .preferredColorScheme(.dark)
}
