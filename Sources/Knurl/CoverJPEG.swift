import AppKit
import CryptoKit
import Foundation

enum CoverJPEG {
    static func make(from image: NSImage) -> (key: String, jpeg: Data)? {
        guard let jpeg = encode(image, edge: 512, quality: 0.70)
            ?? encode(image, edge: 512, quality: 0.55)
            ?? encode(image, edge: 512, quality: 0.40)
            ?? encode(image, edge: 384, quality: 0.55)
        else { return nil }
        let digest = SHA256.hash(data: jpeg)
        let key = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return (key, jpeg)
    }

    private static func encode(_ image: NSImage, edge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = max(edge / size.width, edge / size.height)
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (edge - scaled.width) / 2, y: (edge - scaled.height) / 2)
        let canvas = NSImage(size: CGSize(width: edge, height: edge))
        canvas.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: edge, height: edge)).fill()
        image.draw(
            in: NSRect(origin: origin, size: scaled),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        canvas.unlockFocus()
        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]),
              jpeg.count <= 80_000
        else { return nil }
        return jpeg
    }
}
