public enum PowerMode: String, CaseIterable, Sendable, Identifiable {
    case battery
    case balanced
    case performance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .battery: "Battery"
        case .balanced: "Balanced"
        case .performance: "Performance"
        }
    }

    public var summary: String {
        switch self {
        case .battery:
            "Quieter Knurl motion."
        case .balanced:
            "Normal development."
        case .performance:
            "Full motion for long plugged-in sessions."
        }
    }
}

public enum ThermalBand: String, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    public var title: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        case .unknown: "—"
        }
    }

    public var isException: Bool {
        self == .serious || self == .critical
    }
}

public enum PowerSourceKind: String, Sendable {
    case ac
    case battery
    case unknown

    public var title: String {
        switch self {
        case .ac: "Power Adapter"
        case .battery: "Battery"
        case .unknown: "—"
        }
    }
}

public struct PowerSnapshot: Sendable, Equatable {
    public var percent: Int?
    public var isCharging: Bool
    public var source: PowerSourceKind
    public var minutesRemaining: Int?
    public var thermal: ThermalBand

    public init(
        percent: Int? = nil,
        isCharging: Bool = false,
        source: PowerSourceKind = .unknown,
        minutesRemaining: Int? = nil,
        thermal: ThermalBand = .unknown
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.source = source
        self.minutesRemaining = minutesRemaining
        self.thermal = thermal
    }

    public var percentLabel: String {
        if let percent { return "\(percent)%" }
        return "—"
    }

    public var chargeLabel: String {
        if isCharging { return "Charging" }
        if source == .ac { return "Plugged in" }
        if source == .battery { return "On battery" }
        return "Power"
    }
}
