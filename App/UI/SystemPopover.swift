import AppKit
import CoreKit
import MetricsKit
import SwiftUI

/// 시스템 리소스 메뉴바 아이콘.
struct SystemMenuLabel: View {
    let store: MetricsStore
    let settings: AppSettings

    var body: some View {
        switch settings.systemLabelStyle {
        case .text:
            let cpu = store.menuBar.cpu.map(MetricsFormat.percent) ?? "–"
            let memory = store.menuBar.memory.map(MetricsFormat.percent) ?? "–"
            Text("\(Image(systemName: "cpu")) \(cpu)  \(Image(systemName: "memorychip")) \(memory)")
                .monospacedDigit()
        case .graph:
            Image(nsImage: MenuBarSparkline.image(values: store.menuBar.cpuHistory))
        case .icon:
            Image(systemName: "cpu")
        }
    }
}

/// 스냅샷 확인용: 정해진 모양으로 라벨을 그린다.
struct SystemMenuLabelPreview: View {
    let store: MetricsStore
    let style: SystemLabelStyle

    var body: some View {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "preview.\(style.rawValue)")!)
        settings.systemLabelStyle = style
        return SystemMenuLabel(store: store, settings: settings)
    }
}

/// 시스템 리소스 팝오버.
struct SystemPopover: View {
    let store: MetricsStore
    let settings: AppSettings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("시스템").font(.headline)
                Spacer()
                if let thermal = store.snapshot?.sensors?.thermal, thermal != .nominal {
                    Label(thermal.label, systemImage: "thermometer.high")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(thermal == .fair ? .yellow : .red)
                }
            }

            if let snapshot = store.snapshot, let cpu = snapshot.cpu {
                CPUCard(cpu: cpu, history: store.history.cpu,
                        processes: Array(snapshot.processes.prefix(settings.processCount)))
                if let memory = snapshot.memory {
                    MemoryCard(memory: memory, history: store.history.memory)
                }
                HStack(alignment: .top, spacing: 10) {
                    if let gpu = snapshot.gpu {
                        GPUCard(gpu: gpu, history: store.history.gpu)
                    }
                    if let network = snapshot.network {
                        NetworkCard(network: network, history: store.history.networkDown)
                    }
                }
                if let disk = snapshot.disk { DiskCard(disk: disk) }
                if let battery = snapshot.battery { BatteryCard(battery: battery, sensors: snapshot.sensors) }
                else if let sensors = snapshot.sensors, let soc = sensors.socTemperature {
                    Text("SoC 온도 \(Int(soc.rounded()))℃").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.padding(.vertical, 20)
            }

            Divider()
            HStack {
                Button("활성 상태 보기 열기") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                Spacer()
                Button("설정…") {
                    NSApp.activate()
                    openSettings()
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { store.detailVisible = true }
        .onDisappear { store.detailVisible = false }
    }
}

// MARK: - 카드들

private struct CardHeader: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 4)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

private struct CPUCard: View {
    let cpu: CPUReading
    let history: [Double]
    let processes: [ProcessReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "CPU", value: MetricsFormat.percent(cpu.total),
                       detail: "사용자 \(MetricsFormat.percent(cpu.user)) · 시스템 \(MetricsFormat.percent(cpu.system))")
            Sparkline(values: history, color: statusColor(cpu.total)).frame(height: 30)
            CoreBars(cores: cpu.cores)
            if !processes.isEmpty {
                VStack(spacing: 3) {
                    ForEach(processes) { process in
                        HStack(spacing: 6) {
                            if let icon = AppIcons.icon(for: process.appPath) {
                                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "gearshape").font(.caption2).frame(width: 14, height: 14).foregroundStyle(.secondary)
                            }
                            Text(process.name).font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(String(format: "%.1f%%", process.cpuPercent)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .card()
    }
}

/// 코어별 세로 막대. 효율 코어와 성능 코어를 나눠 보여준다.
private struct CoreBars: View {
    let cores: [CoreReading]

    var body: some View {
        let groups: [(String, [CoreReading])] = [
            ("효율", cores.filter { $0.kind == .efficiency }),
            ("성능", cores.filter { $0.kind == .performance }),
            ("코어", cores.filter { $0.kind == .unknown }),
        ].filter { !$0.1.isEmpty }
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(groups, id: \.0) { name, group in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(group) { core in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(statusColor(core.usage).gradient)
                                    .frame(height: max(22 * core.usage, core.usage > 0.01 ? 2 : 0))
                            }
                            .frame(width: 10, height: 22)
                        }
                    }
                    Text(name).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("코어별 사용률")
    }
}

private struct MemoryCard: View {
    let memory: MemoryReading
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("메모리").font(.subheadline.weight(.semibold))
                Text(memory.pressure.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(pressureColor.opacity(0.25), in: Capsule())
                Spacer(minLength: 4)
                Text("\(MetricsFormat.memory(memory.used)) / \(MetricsFormat.memory(memory.total))")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            // 앱 · 고정 · 압축을 한 막대에
            GeometryReader { proxy in
                let total = Double(max(memory.total, 1))
                HStack(spacing: 1) {
                    segment(Double(memory.app) / total * proxy.size.width, .blue)
                    segment(Double(memory.wired) / total * proxy.size.width, .orange)
                    segment(Double(memory.compressed) / total * proxy.size.width, .purple)
                    Spacer(minLength: 0)
                }
                .background(.quaternary, in: Capsule())
                .clipShape(Capsule())
            }
            .frame(height: 6)
            HStack(spacing: 10) {
                legend("앱", memory.app, .blue)
                legend("고정", memory.wired, .orange)
                legend("압축", memory.compressed, .purple)
                Spacer(minLength: 0)
            }
            Text("스왑 \(MetricsFormat.memory(memory.swapUsed)) · 캐시된 파일 \(MetricsFormat.memory(memory.cached))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var pressureColor: Color {
        switch memory.pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    private func segment(_ width: Double, _ color: Color) -> some View {
        Rectangle().fill(color.gradient).frame(width: max(width, 0))
    }

    private func legend(_ name: String, _ bytes: UInt64, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(MetricsFormat.memory(bytes))").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct GPUCard: View {
    let gpu: Double
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(title: "GPU", value: MetricsFormat.percent(gpu))
            Sparkline(values: history, color: statusColor(gpu)).frame(height: 24)
        }
        .card()
    }
}

private struct NetworkCard: View {
    let network: NetworkReading
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("네트워크").font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 1) {
                Label(MetricsFormat.rate(network.downRate), systemImage: "arrow.down")
                Label(MetricsFormat.rate(network.upRate), systemImage: "arrow.up")
            }
            .font(.caption.monospacedDigit())
            .labelStyle(.titleAndIcon)
            if let name = network.interfaceDisplayName ?? network.interfaceName {
                Text([name, network.address].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .card()
    }
}

private struct DiskCard: View {
    let disk: DiskReading

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(title: "디스크", value: "\(MetricsFormat.storage(disk.available)) 남음", detail: disk.volumeName)
            FractionBar(fraction: disk.usedFraction, color: statusColor(disk.usedFraction))
            Text("전체 \(MetricsFormat.storage(disk.total)) · 읽기 \(MetricsFormat.rate(disk.readRate)) · 쓰기 \(MetricsFormat.rate(disk.writeRate))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .card()
    }
}

private struct BatteryCard: View {
    let battery: BatteryReading
    let sensors: SensorReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(title: "배터리", value: "\(battery.percent)%", detail: state)
            FractionBar(fraction: Double(battery.percent) / 100, color: battery.percent <= 20 ? .red : .green)
            Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var state: String {
        if battery.isCharging {
            return battery.minutesToFull.map { "충전 중 · \(MetricsFormat.duration(minutes: $0)) 후 완료" } ?? "충전 중"
        }
        if battery.onAC { return "전원 연결됨" }
        return battery.minutesRemaining.map { "\(MetricsFormat.duration(minutes: $0)) 남음" } ?? "배터리 사용 중"
    }

    private var details: [String] {
        var parts: [String] = []
        if let health = battery.health { parts.append("최대 용량 \(MetricsFormat.percent(health))") }
        if let cycles = battery.cycleCount { parts.append("충전 \(cycles)회") }
        if let watts = battery.watts, !battery.onAC, watts < 0 { parts.append(String(format: "소비 %.1fW", -watts)) }
        if let adapter = battery.adapterWatts { parts.append("충전기 \(adapter)W") }
        if let soc = sensors?.socTemperature { parts.append("SoC \(Int(soc.rounded()))℃") }
        if let temp = battery.temperature { parts.append("배터리 \(Int(temp.rounded()))℃") }
        return parts
    }
}
