//
//  SystemMonitorManager.swift
//  boringNotch
//
//  System metrics collection using Mach kernel and IOKit APIs.
//

import Combine
import Defaults
import Foundation
import IOKit
import os

/// Widget kinds for the 3-slot System Monitor layout.
enum SystemMonitorWidgetKind: String, CaseIterable, Defaults.Serializable {
    case cpuOverview
    case cpuHistory
    case memoryBreakdown
    case networkLive
    case diskActivity
    case batteryHealth

    var label: String {
        switch self {
        case .cpuOverview: return String(localized: "CPU Overview")
        case .cpuHistory: return String(localized: "CPU History")
        case .memoryBreakdown: return String(localized: "Memory")
        case .networkLive: return String(localized: "Network")
        case .diskActivity: return String(localized: "Disk")
        case .batteryHealth: return String(localized: "Battery Health")
        }
    }
}

/// Centralized system monitor data manager.
@MainActor
class SystemMonitorManager: ObservableObject {

    static let shared = SystemMonitorManager()

    private let logger = Logger(subsystem: "com.dynanotch", category: "SystemMonitor")

    // MARK: - Published CPU

    @Published var cpuUsage: Double = 0
    @Published var cpuHistory: [Double] = []
    @Published var perCoreCPU: [Double] = []

    // MARK: - Published Memory

    @Published var ramTotalGB: Double = 0
    @Published var ramUsedGB: Double = 0
    @Published var ramAppGB: Double = 0
    @Published var ramWiredGB: Double = 0
    @Published var ramCompressedGB: Double = 0

    // MARK: - Published Network

    @Published var netUpSpeed: UInt64 = 0
    @Published var netDownSpeed: UInt64 = 0
    @Published var netUpHistory: [Double] = []
    @Published var netDownHistory: [Double] = []

    // MARK: - Published Disk

    @Published var diskTotalGB: Double = 0
    @Published var diskUsedGB: Double = 0
    @Published var diskReadSpeed: UInt64 = 0
    @Published var diskWriteSpeed: UInt64 = 0

    // MARK: - Published Battery

    @Published var batteryHealth: Double = 100
    @Published var batteryCycleCount: Int = 0
    @Published var batteryCondition: String = ""
    @Published var batteryTemperature: Double? = nil

    // MARK: - Computed

    var isActive: Bool { Defaults[.enableSystemMonitor] }

    var ramUsagePercent: Double {
        guard ramTotalGB > 0 else { return 0 }
        return (ramUsedGB / ramTotalGB) * 100
    }

    var ramFreeGB: Double { max(0, ramTotalGB - ramUsedGB) }

    var diskUsagePercent: Double {
        guard diskTotalGB > 0 else { return 0 }
        return (diskUsedGB / diskTotalGB) * 100
    }

    // MARK: - Private

    private var timer: AnyCancellable?
    private var enabledCancellable: AnyCancellable?

    /// Cached Mach host port — avoids leaking a new send right every call.
    private let hostPort: mach_port_t = mach_host_self()

    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousPerCoreTicks: [(user: Double, system: Double, idle: Double, nice: Double)]?
    private var previousNetBytes: (sent: UInt64, received: UInt64)?
    private var previousNetTimestamp: Date?
    private var previousDiskBytes: (read: UInt64, write: UInt64)?
    private var previousDiskTimestamp: Date?

    private let historyLimit = 30
    /// Counts ticks so slow-changing metrics (battery, disk usage) only refresh every Nth cycle.
    private var tickCount: Int = 0
    private let slowMetricInterval = 5  // every 5 ticks = 10 seconds

    // MARK: - Init

    private init() {
        ramTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0

        enabledCancellable = Defaults.publisher(.enableSystemMonitor)
            .sink { [weak self] change in
                if change.newValue {
                    self?.startMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }

        if Defaults[.enableSystemMonitor] {
            startMonitoring()
        }
    }

    // MARK: - Lifecycle

    private func startMonitoring() {
        logger.info("[SYSMON] start monitoring")
        previousCPUTicks = nil
        previousPerCoreTicks = nil
        previousNetBytes = nil
        previousNetTimestamp = nil
        previousDiskBytes = nil
        previousDiskTimestamp = nil
        tickCount = 0  // ensures first collectMetrics runs slow metrics too

        collectMetrics()

        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.collectMetrics()
            }
    }

    private func stopMonitoring() {
        logger.info("[SYSMON] stop monitoring")
        timer?.cancel()
        timer = nil
    }

    // MARK: - Collection

    private func collectMetrics() {
        // Fast metrics — every 2 seconds
        updateCPU()
        updatePerCoreCPU()
        updateRAM()
        updateNetwork()
        updateDiskIO()

        // Slow metrics — every 10 seconds (battery/disk usage barely change)
        if tickCount % slowMetricInterval == 0 {
            updateDisk()
            updateBattery()
        }
        tickCount += 1
    }

    // MARK: - CPU (Aggregate)

    private func updateCPU() {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &loadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = loadInfo.cpu_ticks.0
        let system = loadInfo.cpu_ticks.1
        let idle = loadInfo.cpu_ticks.2
        let nice = loadInfo.cpu_ticks.3

        if let prev = previousCPUTicks {
            let dUser = user - prev.user
            let dSystem = system - prev.system
            let dIdle = idle - prev.idle
            let dNice = nice - prev.nice
            let total = dUser + dSystem + dIdle + dNice
            if total > 0 {
                cpuUsage = (Double(dUser + dSystem + dNice) / Double(total)) * 100.0
                cpuHistory.append(cpuUsage)
                if cpuHistory.count > historyLimit {
                    cpuHistory.removeFirst(cpuHistory.count - historyLimit)
                }
            }
        }
        previousCPUTicks = (user, system, idle, nice)
    }

    // MARK: - CPU (Per-Core)

    private func updatePerCoreCPU() {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        var coreUsages: [Double] = []
        var currentTicks: [(user: Double, system: Double, idle: Double, nice: Double)] = []

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user = Double(info[offset + Int(CPU_STATE_USER)])
            let system = Double(info[offset + Int(CPU_STATE_SYSTEM)])
            let idle = Double(info[offset + Int(CPU_STATE_IDLE)])
            let nice = Double(info[offset + Int(CPU_STATE_NICE)])

            currentTicks.append((user: user, system: system, idle: idle, nice: nice))

            if let prev = previousPerCoreTicks, i < prev.count {
                let dUser = user - prev[i].user
                let dSystem = system - prev[i].system
                let dIdle = idle - prev[i].idle
                let dNice = nice - prev[i].nice
                let dTotal = dUser + dSystem + dIdle + dNice
                if dTotal > 0 {
                    coreUsages.append(((dUser + dSystem + dNice) / dTotal) * 100.0)
                } else {
                    coreUsages.append(0)
                }
            } else {
                coreUsages.append(0)
            }
        }

        previousPerCoreTicks = currentTicks
        perCoreCPU = coreUsages
    }

    // MARK: - RAM

    private func updateRAM() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let appMemory = active

        ramAppGB = Double(appMemory) / 1_073_741_824.0
        ramWiredGB = Double(wired) / 1_073_741_824.0
        ramCompressedGB = Double(compressed) / 1_073_741_824.0
        ramUsedGB = Double(active + wired + compressed) / 1_073_741_824.0
    }

    // MARK: - Network

    private func updateNetwork() {
        var (totalSent, totalReceived): (UInt64, UInt64) = (0, 0)
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("lo") {
                if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                    let data = unsafeBitCast(addr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                    totalSent += UInt64(data.pointee.ifi_obytes)
                    totalReceived += UInt64(data.pointee.ifi_ibytes)
                }
            }
            ptr = addr.pointee.ifa_next
        }

        let now = Date()
        if let prevBytes = previousNetBytes, let prevTime = previousNetTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let sentDelta = totalSent >= prevBytes.sent ? totalSent - prevBytes.sent : 0
                let receivedDelta = totalReceived >= prevBytes.received ? totalReceived - prevBytes.received : 0
                netUpSpeed = UInt64(Double(sentDelta) / elapsed)
                netDownSpeed = UInt64(Double(receivedDelta) / elapsed)

                netUpHistory.append(Double(netUpSpeed))
                netDownHistory.append(Double(netDownSpeed))
                if netUpHistory.count > historyLimit {
                    netUpHistory.removeFirst(netUpHistory.count - historyLimit)
                }
                if netDownHistory.count > historyLimit {
                    netDownHistory.removeFirst(netDownHistory.count - historyLimit)
                }
            }
        }

        previousNetBytes = (totalSent, totalReceived)
        previousNetTimestamp = now
    }

    // MARK: - Disk (Usage)

    private func updateDisk() {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            if let totalSize = attrs[.systemSize] as? UInt64,
               let freeSize = attrs[.systemFreeSize] as? UInt64 {
                let total = Double(totalSize) / 1_073_741_824.0
                let used = Double(totalSize - freeSize) / 1_073_741_824.0
                if abs(diskTotalGB - total) > 0.01 { diskTotalGB = total }
                if abs(diskUsedGB - used) > 0.01 { diskUsedGB = used }
            }
        } catch {
            logger.warning("[SYSMON] disk usage failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Disk (I/O Speed)

    private func updateDiskIO() {
        let matching = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS {
                if let dict = props?.takeRetainedValue() as? [String: Any],
                   let stats = dict["Statistics"] as? [String: Any] {
                    totalRead += stats["Bytes (Read)"] as? UInt64 ?? 0
                    totalWrite += stats["Bytes (Write)"] as? UInt64 ?? 0
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        let now = Date()
        if let prev = previousDiskBytes, let prevTime = previousDiskTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let readDelta = totalRead >= prev.read ? totalRead - prev.read : 0
                let writeDelta = totalWrite >= prev.write ? totalWrite - prev.write : 0
                diskReadSpeed = UInt64(Double(readDelta) / elapsed)
                diskWriteSpeed = UInt64(Double(writeDelta) / elapsed)
            }
        }

        previousDiskBytes = (read: totalRead, write: totalWrite)
        previousDiskTimestamp = now
    }

    // MARK: - Battery Health

    private func updateBattery() {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return }

        let cycles = dict["CycleCount"] as? Int ?? 0
        if batteryCycleCount != cycles { batteryCycleCount = cycles }

        let maxCap = dict["MaxCapacity"] as? Int ?? 0
        let designCap = dict["DesignCapacity"] as? Int ?? 0
        if designCap > 0 {
            let health = (Double(maxCap) / Double(designCap)) * 100.0
            if abs(batteryHealth - health) > 0.01 { batteryHealth = health }
        }

        if let temp = dict["Temperature"] as? Int {
            let t = Double(temp) / 100.0
            if batteryTemperature != t { batteryTemperature = t }
        }

        let condition: String
        if batteryHealth > 80 {
            condition = String(localized: "Normal")
        } else if batteryHealth > 60 {
            condition = String(localized: "Service Recommended")
        } else {
            condition = String(localized: "Service Required")
        }
        if batteryCondition != condition { batteryCondition = condition }
    }

    // MARK: - Formatting

    static func formatSpeed(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB/s", Double(bytes) / 1_073_741_824.0)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB/s", Double(bytes) / 1_048_576.0)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB/s", Double(bytes) / 1024.0)
        } else {
            return "\(bytes) B/s"
        }
    }

    static func formatGB(_ gb: Double) -> String {
        if gb >= 10 {
            return String(format: "%.0f GB", gb)
        } else {
            return String(format: "%.1f GB", gb)
        }
    }
}
