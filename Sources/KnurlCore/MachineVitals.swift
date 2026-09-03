// Mac only: the phone half of Knurl shares KnurlCore, and neither IOKit
// power management nor `host_processor_info` is available to an iOS app.
#if os(macOS)
import Darwin
import Foundation
import IOKit.pwr_mgt

// MARK: - Vitals
//
// What the Mac is actually doing, sampled from public Darwin interfaces. No
// entitlement, no permission prompt, no helper: `host_processor_info`,
// `host_statistics64`, `getifaddrs` and the volume resource keys are all
// readable by any process about itself and the machine it runs on.

public struct MachineVitals: Equatable, Sendable {
    public var cpu: Double = 0
    public var cores: [Double] = []
    public var memoryUsed: UInt64 = 0
    public var memoryTotal: UInt64 = 0
    public var diskFree: Int64 = 0
    public var diskTotal: Int64 = 0
    public var networkIn: Double = 0
    public var networkOut: Double = 0
    public var uptime: TimeInterval = 0

    public init() {}

    public var memoryProgress: Double {
        memoryTotal == 0 ? 0 : Double(memoryUsed) / Double(memoryTotal)
    }

    public var diskProgress: Double {
        diskTotal == 0 ? 0 : 1 - Double(diskFree) / Double(diskTotal)
    }

    public var cpuLabel: String { "\(Int((cpu * 100).rounded()))%" }
    public var memoryLabel: String { DeskFormat.bytes(memoryUsed) }
    public var memoryDetail: String { "of \(DeskFormat.bytes(memoryTotal))" }
    public var diskLabel: String { DeskFormat.bytes(UInt64(max(0, diskFree))) }
    public var diskDetail: String { "free of \(DeskFormat.bytes(UInt64(max(0, diskTotal))))" }
    public var networkLabel: String { "↓\(DeskFormat.rate(networkIn))  ↑\(DeskFormat.rate(networkOut))" }

    public var uptimeLabel: String {
        let total = Int(uptime)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

public enum DeskFormat {
    public static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: Int64(value))
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 { return "0 KB/s" }
        if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
    }
}

/// Turns the kernel's monotonically-increasing tick counters into a rate. The
/// counters themselves are useless on their own — the interesting number is
/// always the difference between two samples.
public struct CPUSampler {
    public init() {}

    private var previous: [[UInt32]] = []

    public mutating func sample() -> (overall: Double, cores: [Double]) {
        var cpuCount = natural_t(0)
        var infoCount = mach_msg_type_number_t(0)
        var info: processor_info_array_t?
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return (0, []) }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let states = Int(CPU_STATE_MAX)
        let ticks = UnsafeBufferPointer(start: info, count: Int(infoCount))
        var current: [[UInt32]] = []
        var loads: [Double] = []

        for core in 0 ..< Int(cpuCount) {
            let base = core * states
            let sample = (0 ..< states).map { UInt32(bitPattern: ticks[base + $0]) }
            current.append(sample)
            guard core < previous.count else { continue }
            let before = previous[core]
            var busy: Double = 0
            var total: Double = 0
            for state in 0 ..< states {
                let delta = Double(sample[state] &- before[state])
                total += delta
                if state != Int(CPU_STATE_IDLE) { busy += delta }
            }
            loads.append(total > 0 ? min(1, busy / total) : 0)
        }

        previous = current
        let overall = loads.isEmpty ? 0 : loads.reduce(0, +) / Double(loads.count)
        return (overall, loads)
    }
}

public struct NetworkSampler {
    public init() {}

    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var lastAt: Date?

    public mutating func sample() -> (Double, Double) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK)
            else { continue }
            // Loopback would double-count anything the Mac says to itself.
            let name = String(cString: entry.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            guard let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }
            totalIn += UInt64(data.pointee.ifi_ibytes)
            totalOut += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer {
            lastIn = totalIn
            lastOut = totalOut
            lastAt = now
        }
        guard let lastAt else { return (0, 0) }
        let elapsed = now.timeIntervalSince(lastAt)
        guard elapsed > 0.05, totalIn >= lastIn, totalOut >= lastOut else { return (0, 0) }
        return (
            Double(totalIn - lastIn) / elapsed,
            Double(totalOut - lastOut) / elapsed
        )
    }
}


// MARK: - Keep awake
//
// The same mechanism `caffeinate` uses. An assertion is a promise the process
// holds; releasing it — or dying — hands the decision straight back to macOS,
// which is why there is no way for this to leave a Mac permanently awake.

/// A reference type rather than a value type, so the assertion's lifetime is
/// exactly the object's lifetime: dropping the last reference releases it,
/// and there is no way to copy the handle and double-release it.
public final class KeepAwakeAssertion {
    private let id: IOPMAssertionID

    public init?(reason: String = "Knurl is keeping this Mac awake") {
        var created: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &created
        )
        guard result == kIOReturnSuccess else { return nil }
        id = created
    }

    deinit {
        IOPMAssertionRelease(id)
    }
}
#endif
