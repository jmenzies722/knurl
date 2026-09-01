import Foundation

public enum KnurlBonjour: Sendable {
    public static let serviceType = "_knurl._tcp"
    public static let serviceName = "Knurl"
}

public enum CrownAction: String, Codable, Sendable {
    case rotate
    case confirm
    case select
    case hello
}

public struct CrownRequest: Codable, Sendable, Equatable {
    public var action: CrownAction
    public var detents: Int?
    public var mode: String?

    public init(action: CrownAction, detents: Int? = nil, mode: String? = nil) {
        self.action = action
        self.detents = detents
        self.mode = mode
    }
}

public struct CrownHello: Codable, Sendable, Equatable {
    public var host: String
    public var mode: String
    public var readout: String
    public var progress: Double
    public var target: String

    public init(host: String, mode: String, readout: String, progress: Double, target: String) {
        self.host = host
        self.mode = mode
        self.readout = readout
        self.progress = progress
        self.target = target
    }
}

public enum CrownJSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public static let decoder = JSONDecoder()
}
