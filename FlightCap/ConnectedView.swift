//
//  ConnectedView.swift
//  FlightCap
//

import SwiftUI
import Charts

struct ConnectedView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        VStack(spacing: 16) {
            header

            TelemetryChart(
                title: "Motion",
                subtitle: motionSubtitle,
                accent: Theme.motion,
                samples: ble.motionSamples,
                yLabel: "events / sec"
            )

            TelemetryChart(
                title: "Distance",
                subtitle: distanceSubtitle,
                accent: Theme.distance,
                samples: ble.distanceSamples,
                yLabel: "mm"
            )

            clearButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
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
            Text("Connected to FlightCap")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button(action: { ble.disconnect() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Disconnect")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color.red.opacity(0.85))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var motionSubtitle: String {
        if let v = ble.motionSamples.last?.value, !v.isNaN {
            return "\(Int(v)) ev/s"
        }
        return "---"
    }

    private var distanceSubtitle: String {
        guard let last = ble.distanceSamples.last else { return "---" }
        if last.value.isNaN { return "invalid" }
        return "\(Int(last.value)) mm"
    }
}

private struct TelemetryChart: View {
    let title: String
    let subtitle: String
    let accent: Color
    let samples: [Sample]
    let yLabel: String

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
                ForEach(samples) { s in
                    LineMark(
                        x: .value("Sample", s.id),
                        y: .value(yLabel, s.value)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Sample", s.id),
                        y: .value(yLabel, s.value)
                    )
                    .foregroundStyle(accent)
                    .symbolSize(28)
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisTick().foregroundStyle(Color.white.opacity(0.2))
                    AxisValueLabel().foregroundStyle(Theme.dim)
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

    private var xDomain: ClosedRange<Int> {
        let last = samples.last?.id ?? 0
        let window = BLEManager.windowSize - 1
        return last < window ? 0...window : (last - window)...last
    }

    /// Pad the y-domain a bit so the line doesn't kiss the axes. Falls back to
    /// a small range when there are no valid samples yet.
    private var yDomain: ClosedRange<Double> {
        let finite = samples.compactMap { $0.value.isFinite ? $0.value : nil }
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
