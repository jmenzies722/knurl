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
    case skip
    case shuffle
    case `repeat`
    case pick
    case talkStart
    case talkEnd
    case talkCancel
}

public struct CrownRequest: Codable, Sendable, Equatable {
    public var action: CrownAction
    public var detents: Int?
    public var mode: String?
    public var progress: Double?
    public var name: String?

    public init(
        action: CrownAction,
        detents: Int? = nil,
        mode: String? = nil,
        progress: Double? = nil,
        name: String? = nil
    ) {
        self.action = action
        self.detents = detents
        self.mode = mode
        self.progress = progress
        self.name = name
    }
}

public struct CrownDevice: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String

    public init(id: String, name: String, kind: String) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct CrownHello: Codable, Sendable, Equatable {
    public var host: String
    public var mode: String
    public var readout: String
    public var progress: Double
    public var target: String
    public var muted: Bool?
    public var playing: Bool?
    public var duration: Double?
    public var title: String?
    public var album: String?
    public var genre: String?
    public var shuffle: Bool?
    public var `repeat`: String?
    public var artKey: String?
    public var art: String?
    public var playlists: [String]?
    public var devices: [CrownDevice]?
    public var deviceUID: String?
    public var destination: String?
    public var listening: Bool?
    public var preview: String?

    public init(
        host: String,
        mode: String,
        readout: String,
        progress: Double,
        target: String,
        muted: Bool? = nil,
        playing: Bool? = nil,
        duration: Double? = nil,
        title: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        shuffle: Bool? = nil,
        repeat: String? = nil,
        artKey: String? = nil,
        art: String? = nil,
        playlists: [String]? = nil,
        devices: [CrownDevice]? = nil,
        deviceUID: String? = nil,
        destination: String? = nil,
        listening: Bool? = nil,
        preview: String? = nil
    ) {
        self.host = host
        self.mode = mode
        self.readout = readout
        self.progress = progress
        self.target = target
        self.muted = muted
        self.playing = playing
        self.duration = duration
        self.title = title
        self.album = album
        self.genre = genre
        self.shuffle = shuffle
        self.repeat = `repeat`
        self.artKey = artKey
        self.art = art
        self.playlists = playlists
        self.devices = devices
        self.deviceUID = deviceUID
        self.destination = destination
        self.listening = listening
        self.preview = preview
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
