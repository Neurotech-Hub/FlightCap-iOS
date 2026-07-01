//
//  ConnectedView.swift
//  FlightCap
//

import SwiftUI
import Charts
import UIKit

struct ConnectedView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var now = Date()
    @State private var showShareSheet = false
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            header
            batteryStrip

            TelemetryChart(
                title: "Motion",
                subtitle: motionSubtitle,
                accent: Theme.motion,
                records: ble.records,
                flagTimestamps: visibleFlags,
                chartWindowMinutes: ble.chartWindowMinutes,
                yLabel: "interactions",
                valueKeyPath: \.interactions,
                now: now
            )

            TelemetryChart(
                title: "Distance",
                subtitle: distanceSubtitle,
                accent: Theme.distance,
                records: ble.records,
                flagTimestamps: visibleFlags,
                chartWindowMinutes: ble.chartWindowMinutes,
                yLabel: "mm",
                valueKeyPath: \.distanceMm,
                now: now
            )

            bottomToolbar
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            now = tick
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL {
                ActivityShareSheet(items: [exportURL])
            }
        }
    }

    private var visibleFlags: [Date] {
        let window = ble.chartWindowMinutes * 60
        let cutoff = now.addingTimeInterval(-window)
        return ble.flagTimestamps.filter { $0 >= cutoff }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(ble.chartWindowMinutes))m")
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.dim)
                Slider(
                    value: $ble.chartWindowMinutes,
                    in: BLEManager.minChartMinutes...BLEManager.maxChartMinutes,
                    step: 1
                )
                .tint(Theme.motion)
            }

            toolbarButton(title: "Flag", icon: "flag.fill", fill: Color.red.opacity(0.85)) {
                ble.flagNow()
            }

            toolbarButton(title: "Clear", icon: "arrow.clockwise", fill: Color.white.opacity(0.12)) {
                ble.clearPlots()
            }
        }
        .padding(.horizontal, 4)
    }

    private func toolbarButton(title: String, icon: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(width: 64)
            .padding(.vertical, 10)
            .background(Capsule().fill(fill))
            .overlay(
                Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

            Button(action: shareExport) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(ble.records.isEmpty)

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

    private func shareExport() {
        guard let url = ble.exportFileURL() else { return }
        exportURL = url
        showShareSheet = true
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
        if let v = latestInteractions {
            return "\(v) interactions"
        }
        return "---"
    }

    private var distanceSubtitle: String {
        guard let v = latestDistanceMm else { return "---" }
        return "\(v) mm"
    }

    private var latestInteractions: Int? {
        ble.records.last(where: { $0.interactions != nil })?.interactions
    }

    private var latestDistanceMm: Int? {
        ble.records.last(where: { $0.distanceMm != nil })?.distanceMm
    }
}

private struct TelemetryChart: View {
    let title: String
    let subtitle: String
    let accent: Color
    let records: [TelemetryRecord]
    let flagTimestamps: [Date]
    let chartWindowMinutes: Double
    let yLabel: String
    let valueKeyPath: KeyPath<TelemetryRecord, Int?>
    let now: Date

    private var plottableRecords: [(timestamp: Date, value: Double)] {
        let cutoff = now.addingTimeInterval(-chartWindowMinutes * 60)
        return records.compactMap { r in
            guard r.timestamp >= cutoff, let v = r[keyPath: valueKeyPath] else { return nil }
            return (r.timestamp, Double(v))
        }
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
                ForEach(flagTimestamps, id: \.self) { t in
                    RuleMark(x: .value("Flag", t))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }

                ForEach(Array(plottableRecords.enumerated()), id: \.offset) { _, point in
                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value(yLabel, point.value)
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
        let start = end.addingTimeInterval(-chartWindowMinutes * 60)
        return start...end
    }

    private var yDomain: ClosedRange<Double> {
        let values = plottableRecords.map(\.value)
        guard let lo = values.min(), let hi = values.max() else {
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

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let mgr = BLEManager()
    return ZStack {
        Theme.background.ignoresSafeArea()
        ConnectedView().environmentObject(mgr)
    }
    .preferredColorScheme(.dark)
}
