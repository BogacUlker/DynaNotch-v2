//
//  SystemMonitorView.swift
//  boringNotch
//
//  System Monitor tab with configurable widget slots.
//

import Defaults
import SwiftUI

// MARK: - Main View

struct SystemMonitorView: View {
    @ObservedObject var manager = SystemMonitorManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(spacing: 8) {
            widgetForSlot(Defaults[.sysMonSlot1])
            widgetForSlot(Defaults[.sysMonSlot2])
            widgetForSlot(Defaults[.sysMonSlot3])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        ))
    }

    @ViewBuilder
    private func widgetForSlot(_ kind: SystemMonitorWidgetKind) -> some View {
        switch kind {
        case .cpuOverview: CPUOverviewWidget()
        case .cpuHistory: CPUHistoryWidget()
        case .memoryBreakdown: MemoryWidget()
        case .networkLive: NetworkWidget()
        case .diskActivity: DiskWidget()
        case .batteryHealth: BatteryHealthWidget()
        }
    }
}

// MARK: - CPU Overview Widget

private struct CPUOverviewWidget: View {
    @ObservedObject var manager = SystemMonitorManager.shared

    private var cpuColor: Color {
        if manager.cpuUsage < 50 { return .green }
        if manager.cpuUsage < 80 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 2).frame(maxHeight: 8)

            // Gauge ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(manager.cpuUsage / 100.0, 1.0))
                    .stroke(
                        AngularGradient(
                            colors: [cpuColor.opacity(0.6), cpuColor],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * min(manager.cpuUsage / 100.0, 1.0))
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: manager.cpuUsage)

                VStack(spacing: 0) {
                    Text("\(Int(manager.cpuUsage))%")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("CPU")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(cpuColor)
                }
            }
            .frame(width: 72, height: 72)

            Spacer(minLength: 0)

            // Per-core bars
            if !manager.perCoreCPU.isEmpty {
                PerCoreBarsView(cores: manager.perCoreCPU)
                    .frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Per-Core Bars

private struct PerCoreBarsView: View {
    let cores: [Double]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, usage in
                GeometryReader { geo in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(colorFor(usage))
                            .frame(height: max(1, geo.size.height * CGFloat(min(usage / 100.0, 1.0))))
                    }
                }
            }
        }
    }

    private func colorFor(_ usage: Double) -> Color {
        if usage < 50 { return .green }
        if usage < 80 { return .orange }
        return .red
    }
}

// MARK: - CPU History Widget

private struct CPUHistoryWidget: View {
    @ObservedObject var manager = SystemMonitorManager.shared

    private var cpuColor: Color {
        if manager.cpuUsage < 50 { return .green }
        if manager.cpuUsage < 80 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "cpu")
                    .font(.system(size: 9))
                    .foregroundColor(cpuColor)
                Text("CPU History")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                Text("\(Int(manager.cpuUsage))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            AreaChartView(
                data: manager.cpuHistory,
                maxValue: 100,
                lineColor: cpuColor,
                fillColor: cpuColor.opacity(0.2)
            )

            if manager.cpuHistory.count > 1 {
                HStack {
                    Text("Avg: \(Int(manager.cpuHistory.reduce(0, +) / Double(manager.cpuHistory.count)))%")
                    Spacer()
                    Text("Peak: \(Int(manager.cpuHistory.max() ?? 0))%")
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Memory Widget

private struct MemoryWidget: View {
    @ObservedObject var manager = SystemMonitorManager.shared

    private var ramColor: Color {
        let pct = manager.ramUsagePercent
        if pct < 60 { return .cyan }
        if pct < 85 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "memorychip")
                    .font(.system(size: 11))
                    .foregroundColor(ramColor)
                Text("Memory")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                Text("\(Int(manager.ramUsagePercent))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Stacked bar
            GeometryReader { geo in
                let total = max(manager.ramTotalGB, 0.01)
                let appW = geo.size.width * CGFloat(manager.ramAppGB / total)
                let wiredW = geo.size.width * CGFloat(manager.ramWiredGB / total)
                let compW = geo.size.width * CGFloat(manager.ramCompressedGB / total)

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: max(0, appW))
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: max(0, wiredW))
                    Rectangle()
                        .fill(Color.purple)
                        .frame(width: max(0, compW))
                    Spacer(minLength: 0)
                }
                .frame(height: geo.size.height)
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 8)

            // Breakdown
            VStack(alignment: .leading, spacing: 3) {
                memRow(color: .blue, label: String(localized: "App"), value: SystemMonitorManager.formatGB(manager.ramAppGB))
                memRow(color: .orange, label: String(localized: "Wired"), value: SystemMonitorManager.formatGB(manager.ramWiredGB))
                memRow(color: .purple, label: String(localized: "Compressed"), value: SystemMonitorManager.formatGB(manager.ramCompressedGB))
                memRow(color: .gray.opacity(0.4), label: String(localized: "Free"), value: SystemMonitorManager.formatGB(manager.ramFreeGB))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    private func memRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Network Widget

private struct NetworkWidget: View {
    @ObservedObject var manager = SystemMonitorManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 9))
                    .foregroundColor(.cyan)
                Text("Network")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
            }

            // Dual-line chart
            if manager.netDownHistory.count > 1 || manager.netUpHistory.count > 1 {
                let maxVal = max(
                    manager.netDownHistory.max() ?? 1,
                    manager.netUpHistory.max() ?? 1,
                    1
                )
                ZStack {
                    AreaChartView(
                        data: manager.netDownHistory,
                        maxValue: maxVal,
                        lineColor: .cyan,
                        fillColor: .cyan.opacity(0.15)
                    )
                    AreaChartView(
                        data: manager.netUpHistory,
                        maxValue: maxVal,
                        lineColor: .purple,
                        fillColor: .purple.opacity(0.1)
                    )
                }
            } else {
                Spacer()
            }

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.cyan)
                    Text(SystemMonitorManager.formatSpeed(manager.netDownSpeed))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.purple)
                    Text(SystemMonitorManager.formatSpeed(manager.netUpSpeed))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Disk Widget

private struct DiskWidget: View {
    @ObservedObject var manager = SystemMonitorManager.shared

    private var diskColor: Color {
        let pct = manager.diskUsagePercent
        if pct < 70 { return .teal }
        if pct < 90 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 9))
                    .foregroundColor(diskColor)
                Text("Disk")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                Text("\(Int(manager.diskUsagePercent))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Usage bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(diskColor)
                        .frame(width: max(0, geo.size.width * CGFloat(min(manager.diskUsagePercent / 100.0, 1.0))))
                        .animation(.easeInOut(duration: 0.4), value: manager.diskUsagePercent)
                }
            }
            .frame(height: 6)

            Text("\(SystemMonitorManager.formatGB(manager.diskUsedGB)) / \(SystemMonitorManager.formatGB(manager.diskTotalGB))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.gray)

            Spacer(minLength: 0)

            // I/O speeds
            VStack(alignment: .leading, spacing: 2) {
                ioRow(icon: "arrow.down.doc", label: String(localized: "Read"), value: SystemMonitorManager.formatSpeed(manager.diskReadSpeed), color: .green)
                ioRow(icon: "arrow.up.doc", label: String(localized: "Write"), value: SystemMonitorManager.formatSpeed(manager.diskWriteSpeed), color: .orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    private func ioRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 7))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
}

// MARK: - Battery Health Widget

private struct BatteryHealthWidget: View {
    @ObservedObject var manager = SystemMonitorManager.shared

    private var healthColor: Color {
        if manager.batteryHealth > 80 { return .green }
        if manager.batteryHealth > 60 { return .yellow }
        return .red
    }

    var body: some View {
        VStack(spacing: 6) {
            // Health gauge
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(manager.batteryHealth / 100.0, 1.0))
                    .stroke(
                        AngularGradient(
                            colors: [healthColor.opacity(0.6), healthColor],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * min(manager.batteryHealth / 100.0, 1.0))
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(Int(manager.batteryHealth))%")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Health")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(healthColor)
                }
            }
            .frame(width: 56, height: 56)

            VStack(spacing: 2) {
                statRow(label: String(localized: "Cycles"), value: "\(manager.batteryCycleCount)")
                statRow(label: String(localized: "Status"), value: manager.batteryCondition)
                if let temp = manager.batteryTemperature {
                    statRow(label: String(localized: "Temp"), value: String(format: "%.0f\u{00B0}C", temp))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Area Chart (Reusable)

struct AreaChartView: View {
    let data: [Double]
    let maxValue: Double
    let lineColor: Color
    let fillColor: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let maxVal = max(maxValue, 1)

            ZStack {
                // Fill area
                Path { path in
                    guard data.count > 1 else { return }
                    let stepX = width / CGFloat(data.count - 1)

                    path.move(to: CGPoint(x: 0, y: height))
                    for (i, value) in data.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = height * (1.0 - CGFloat(min(value / maxVal, 1.0)))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: CGFloat(data.count - 1) * stepX, y: height))
                    path.closeSubpath()
                }
                .fill(fillColor)

                // Line
                Path { path in
                    guard data.count > 1 else { return }
                    let stepX = width / CGFloat(data.count - 1)

                    for (i, value) in data.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = height * (1.0 - CGFloat(min(value / maxVal, 1.0)))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
