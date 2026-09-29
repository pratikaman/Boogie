import AppKit
import ImageIO

struct Companion: Identifiable {
    let id: String
    let name: String
    let detail: String
    let realistic: Bool
}

/// Scanned people and the original, procedural pixel cast.
enum Companions {
    static let people = [
        Companion(id: "sophia", name: "Sophia", detail: "Light layers", realistic: true),
        Companion(id: "manuel", name: "Manuel", detail: "Grey tee", realistic: true),
        Companion(id: "carla", name: "Carla", detail: "Tailored blazer", realistic: true),
        Companion(id: "nathan", name: "Nathan", detail: "White tee", realistic: true)
    ]
    static let classics = Cast.roster.map { Companion(id: $0.id, name: $0.name, detail: "Pixel original", realistic: false) }
    private static var portraits: [String: CGImage] = [:]
    static func find(_ id: String) -> Companion { (people + classics).first { $0.id == id } ?? people[0] }
    static func roster(for id: String) -> [Companion] { find(id).realistic ? people : classics }
    static func size(for id: String, scale: Int) -> CGSize {
        find(id).realistic ? CGSize(width: 48 * scale, height: 64 * scale)
                          : CGSize(width: PixelCanvas.width * scale, height: PixelCanvas.height * scale)
    }
    static func footInset(for id: String, scale: Int) -> CGFloat {
        find(id).realistic ? CGFloat(64 * scale) * 0.06 : CGFloat(4 * scale)
    }
    static func portrait(_ id: String) -> CGImage? {
        if let image = portraits[id] { return image }
        if find(id).realistic {
            guard let image = CharacterFrames.shared.frame(id: id, phase: 9.0),
                  let context = CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            // A standalone thumbnail avoids retaining a full atlas page for every
            // picker tile, or displacing the playing clips on each SwiftUI update.
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let thumbnail = context.makeImage()
            portraits[id] = thumbnail
            return thumbnail
        }
        var canvas = PixelCanvas()
        let renderer = SpriteRenderer(look: Cast.look(id, fit: Wardrobe.fits[0], skin: Wardrobe.skins[1]))
        renderer.draw(Moves.disco.pose(MoveContext(beat: 0.1)), bunLag: 0, hearts: [], into: &canvas)
        return canvas.cgImage()
    }
}

/// Lazy, bounded atlas cache shared by the Dock windows and control-panel preview.
/// No networking or 3D runtime is needed to play the rendered characters.
final class CharacterFrames {
    struct Manifest: Decodable {
        struct Clip: Decodable { let start: Int; let count: Int }
        let width: Int
        let height: Int
        let columns: Int
        let rows: Int
        let fps: Double
        let clips: [String: Clip]
    }
    static let shared = CharacterFrames()
    private let pages = NSCache<NSString, CGImage>()
    private var manifests: [String: Manifest] = [:]
    private var missing = Set<String>()
    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? Bundle.main.resourceURL!.appendingPathComponent("Characters")
        pages.totalCostLimit = 64 * 1024 * 1024
        pages.countLimit = 5
    }

    func manifest(_ id: String) -> Manifest? {
        if let cached = manifests[id] { return cached }
        guard !missing.contains(id) else { return nil }
        let url = root.appendingPathComponent(id).appendingPathComponent("animation.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.width > 0, manifest.height > 0, manifest.columns > 0, manifest.rows > 0,
              manifest.fps > 0, manifest.clips["dance"]?.count ?? 0 > 0 else {
            missing.insert(id)
            NSLog("Boogie: missing or invalid animation for %@", id)
            return nil
        }
        manifests[id] = manifest
        return manifest
    }

    func frame(id: String, phase: Double, clip name: String = "dance") -> CGImage? {
        guard phase.isFinite, let m = manifest(id), let clip = m.clips[name], clip.count > 0 else { return nil }
        let offset = Int(max(0, phase) * m.fps) % clip.count
        return image(id: id, manifest: m, clip: clip, offset: offset)
    }

    func frame(id: String, progress: Double, clip name: String) -> CGImage? {
        guard progress.isFinite, let m = manifest(id), let clip = m.clips[name], clip.count > 0 else { return nil }
        let normalized = max(0, progress).truncatingRemainder(dividingBy: 1)
        return image(id: id, manifest: m, clip: clip, offset: min(clip.count - 1, Int(normalized * Double(clip.count))))
    }

    private func image(id: String, manifest m: Manifest, clip: Manifest.Clip, offset: Int) -> CGImage? {
        let index = clip.start + offset
        let perPage = m.columns * m.rows
        let key = "\(id)/\(index / perPage)" as NSString
        let page: CGImage
        if let cached = pages.object(forKey: key) {
            page = cached
        } else {
            let path = root.appendingPathComponent(id).appendingPathComponent(String(format: "atlas-%03d.png", index / perPage))
            guard let source = CGImageSourceCreateWithURL(path as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                  image.width == m.columns * m.width, image.height == m.rows * m.height else { return nil }
            page = image
            pages.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        }
        let cell = index % perPage
        return page.cropping(to: CGRect(x: (cell % m.columns) * m.width, y: (cell / m.columns) * m.height,
                                       width: m.width, height: m.height))
    }
}

/// Both previews and desktop dancers advance using the same beat clock.
final class CompanionPlayback {
    func frame(id: String, sample: DanceSample, duck: Int = 0) -> CGImage? {
        CharacterFrames.shared.frame(id: id, progress: sample.progress,
                                     clip: duck > 0 ? "duck\(duck)" : sample.routine.id)
    }
}
