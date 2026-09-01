import Foundation
import IOKit.ps
import KnurlCore
import Observation

@MainActor
@Observable
final class PowerWatch {
    private(set) var snapshot = PowerSnapshot()
    var onChange: ((PowerSnapshot) -> Void)?

    private var loopSource: CFRunLoopSource?
    private var thermalObserver: NSObjectProtocol?

    func start() {
        refresh()
        if loopSource == nil {
            let callback: IOPowerSourceCallbackType = { context in
                guard let context else { return }
                let watch = Unmanaged<PowerWatch>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in
                    watch.refresh()
                }
            }
            let source = IOPSNotificationCreateRunLoopSource(
                callback,
                Unmanaged.passUnretained(self).toOpaque()
            )?.takeRetainedValue()
            if let source {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
                loopSource = source
            }
        }
        if thermalObserver == nil {
            thermalObserver = NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }
    }

    func refresh() {
        let next = Self.read()
        if next != snapshot {
            snapshot = next
            onChange?(next)
        }
    }

    private static func read() -> PowerSnapshot {
        var percent: Int?
        var charging = false
        var source: PowerSourceKind = .unknown
        var minutes: Int?

        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        {
            for item in list {
                guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any] else {
                    continue
                }
                if let capacity = description[kIOPSCurrentCapacityKey] as? Int {
                    percent = capacity
                }
                if let flag = description[kIOPSIsChargingKey] as? Bool {
                    charging = flag
                }
                if let state = description[kIOPSPowerSourceStateKey] as? String {
                    if state == kIOPSACPowerValue {
                        source = .ac
                    } else if state == kIOPSBatteryPowerValue {
                        source = .battery
                    }
                }
                if let remaining = description[kIOPSTimeToEmptyKey] as? Int, remaining > 0 {
                    minutes = remaining
                }
                if percent != nil { break }
            }
        }

        return PowerSnapshot(
            percent: percent,
            isCharging: charging,
            source: source,
            minutesRemaining: minutes,
            thermal: thermalBand(ProcessInfo.processInfo.thermalState)
        )
    }

    private static func thermalBand(_ state: ProcessInfo.ThermalState) -> ThermalBand {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }
}
