import Foundation
import KnurlLink
import Testing

@Suite("Crown link")
struct CrownLinkTests {
    @Test func helloWithArtRoundTrips() throws {
        let hello = CrownHello(
            host: "Josh-MacBook-Pro",
            mode: "media",
            readout: "1:12",
            progress: 0.4,
            target: "Artist",
            playing: true,
            duration: 180,
            title: "Song",
            album: "Album",
            genre: "Jazz",
            shuffle: true,
            repeat: "all",
            artKey: "aabbccdd11223344",
            art: Data([0xFF, 0xD8, 0xFF]).base64EncodedString(),
            playlists: ["Focus"],
            devices: nil,
            deviceUID: nil
        )
        let data = try CrownJSON.encoder.encode(hello)
        let decoded = try CrownJSON.decoder.decode(CrownHello.self, from: data)
        #expect(decoded.artKey == "aabbccdd11223344")
        #expect(decoded.art != nil)
        #expect(decoded.shuffle == true)
        #expect(decoded.repeat == "all")
        #expect(decoded.playlists == ["Focus"])
    }

    @Test func helloArtKeyOnlyOmitsJPEG() throws {
        let hello = CrownHello(
            host: "Mac",
            mode: "media",
            readout: "Now",
            progress: 0.1,
            target: "A",
            artKey: "deadbeefdeadbeef"
        )
        let data = try CrownJSON.encoder.encode(hello)
        let decoded = try CrownJSON.decoder.decode(CrownHello.self, from: data)
        #expect(decoded.artKey == "deadbeefdeadbeef")
        #expect(decoded.art == nil)
    }

    @Test func newActionsEncode() throws {
        let actions: [CrownRequest] = [
            CrownRequest(action: .skip, detents: 1),
            CrownRequest(action: .shuffle),
            CrownRequest(action: .repeat),
            CrownRequest(action: .pick, name: "Focus"),
            CrownRequest(action: .talkStart),
            CrownRequest(action: .talkEnd),
            CrownRequest(action: .talkCancel),
        ]
        for request in actions {
            let data = try CrownJSON.encoder.encode(request)
            let decoded = try CrownJSON.decoder.decode(CrownRequest.self, from: data)
            #expect(decoded.action == request.action)
            #expect(decoded.detents == request.detents)
            #expect(decoded.name == request.name)
        }
    }

    @Test func oldHelloStillDecodes() throws {
        let data = Data(#"{"host":"Mac","mode":"volume","progress":0.5,"readout":"40","target":"Volume"}"#.utf8)
        let hello = try CrownJSON.decoder.decode(CrownHello.self, from: data)
        #expect(hello.mode == "volume")
        #expect(hello.art == nil)
        #expect(hello.playlists == nil)
        #expect(hello.destination == nil)
        #expect(hello.listening == nil)
    }

    @Test func destinationAndTalkRoundTrip() throws {
        let hello = CrownHello(
            host: "Mac",
            mode: "mic",
            readout: "62",
            progress: 0.62,
            target: "Mic",
            destination: "Cursor",
            listening: true,
            preview: "open the file"
        )
        let decoded = try CrownJSON.decoder.decode(
            CrownHello.self,
            from: try CrownJSON.encoder.encode(hello)
        )
        #expect(decoded.destination == "Cursor")
        #expect(decoded.listening == true)
        #expect(decoded.preview == "open the file")
    }
}
