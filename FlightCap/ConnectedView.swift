//
//  ConnectedView.swift
//  FlightCap
//

import SwiftUI
import Charts

struct ConnectedView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var now = Date()

    var body: some View {
        VStack(spacing: 16) {
            header
            batteryStrip

            TelemetryChart(
                title: "Motion",
                subtitle: motionSubtitle,
                accent: Theme.motion,
                samples: ble.motionSamples,
                yLabel: "interactions",
                now: now
            )

            TelemetryChart(
                title: "Distance",
                subtitle: distanceSubtitle,
                accent: Theme.distance,
                samples: ble.distanceSamples,
                yLabel: "mm",
                now: now
            )

            clearButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            now = tick
        }
    }

    private var clearButton: some View {
        Button(action: { ble.clearPlots() }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .bold))
                Text("Clear Plots")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(Color.white.opacity(0.12))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
                .shadow(color: .green.opacity(0.8), radius: 6)

            Text(listeningTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Button(action: { ble.leaveListening() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    Text("Back")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color.white.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var batteryStrip: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "battery.100")
                    .foregroundStyle(Theme.motion)
                Text(batterySubtitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(Theme.distance)
                Text(lastDataSubtitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.panel)
        )
        .padding(.horizontal, 4)
    }

    private var listeningTitle: String {
        if let name = ble.selectedCap?.displayName {
            return "Listening to \(name)"
        }
        return "Listening"
    }

    private var batterySubtitle: String {
        guard ble.latestVbattValid, let mv = ble.latestVbattMv else { return "---" }
        return String(format: "%.2fV", Double(mv) / 1000.0)
    }

    private var lastDataSubtitle: String {
        guard let received = ble.lastDataReceived else { return "---" }
        let seconds = max(0, Int(now.timeIntervalSince(received)))
        if seconds == 1 {
            return "1s ago"
        }
        return "\(seconds)s ago"
    }

    private var motionSubtitle: String {
        if let v = latestFiniteValue(in: ble.motionSamples), !v.isNaN {
            return "\(Int(v)) interactions"
        }
        return "---"
    }

    private var distanceSubtitle: String {
        guard let v = latestFiniteValue(in: ble.distanceSamples) else { return "---" }
        if v.isNaN { return "invalid" }
        return "\(Int(v)) mm"
    }

    private func latestFiniteValue(in samples: [Sample]) -> Double? {
        samples.last(where: { $0.value.isFinite })?.value
    }
}

private struct TelemetryChart: View {
    let title: String
    let subtitle: String
    let accent: Color
    let samples: [Sample]
    let yLabel: String
    let now: Date

    private var plottableSamples: [Sample] {
        let cutoff = now.addingTimeInterval(-BLEManager.plotWindow)
        return samples.filter { $0.timestamp >= cutoff && $0.value.isFinite }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
            }

            Chart {
                ForEach(plottableSamples) { s in
                    PointMark(
                        x: .value("Time", s.timestamp),
                        y: .value(yLabel, s.value)
                    )
                    .foregroundStyle(accent)
                    .symbolSize(36)
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisTick().foregroundStyle(Color.white.opacity(0.2))
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.minute().second())
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisTick().foregroundStyle(Color.white.opacity(0.2))
                    AxisValueLabel().foregroundStyle(Theme.dim)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.15), radius: 12, x: 0, y: 6)
    }

    private var xDomain: ClosedRange<Date> {
        let end = now
        let start = end.addingTimeInterval(-BLEManager.plotWindow)
        return start...end
    }

    private var yDomain: ClosedRange<Double> {
        let finite = plottableSamples.map(\.value)
        guard let lo = finite.min(), let hi = finite.max() else {
            return 0...1
        }
        if lo == hi {
            let pad = max(1.0, abs(lo) * 0.1)
            return (lo - pad)...(hi + pad)
        }
        let span = hi - lo
        let pad = span * 0.15
        let lower = min(0, lo - pad)
        return lower...(hi + pad)
    }
}

#Preview {
    let mgr = BLEManager()
    return ZStack {
        Theme.background.ignoresSafeArea()
        ConnectedView().environmentObject(mgr)
    }
    .preferredColorScheme(.dark)
}
