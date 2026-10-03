import AppKit
import ImageIO
import Vision

/// Local raster animation: legacy eight-pose sheets or full 24 fps video clips.
/// Neither format contains an editable or rotatable 3D mesh.
struct GeneratedDance: Codable {
    let frames: [Data]
    var frameRate: Double? = nil
    var isVideo: Bool { frameRate != nil }
    var duration: Double { Double(frames.count) / (frameRate ?? 8) }

    func validated() throws -> GeneratedDance {
        let validTiming = frameRate.map { $0.isFinite && $0 == 24 && (24...192).contains(frames.count) } ?? (frames.count == 8)
        guard validTiming, frames.reduce(0, { $0 + $1.count }) <= (isVideo ? 48_000_000 : 8_000_000),
              frames.allSatisfy({ Self.decode($0) != nil }) else { throw LikenessError.invalidSheet }
        return self
    }

    static func decode(_ data: Data) -> CGImage? {
        guard data.count <= 1_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == 384,
              properties[kCGImagePropertyPixelHeight] as? Int == 512 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func fromSheet(_ sheet: CGImage) throws -> GeneratedDance {
        guard sheet.width >= 1024, sheet.height >= 768, sheet.width <= 4096, sheet.height <= 4096 else { throw LikenessError.invalidSheet }
        var sheet = sheet
        var regions = subjectRegions(sheet)
        if regions.count != 8, let cutout = try? PhotoImport.removeBackground(sheet, cropped: false) {
            sheet = cutout
            regions = subjectRegions(sheet)
        }
        guard regions.count == 8 else { throw LikenessError.invalidSheet }
        let w = sheet.width / 4, h = sheet.height / 2
        var poses: [(image: CGImage, bounds: CGRect, anchor: CGFloat)] = []
        for index in 0..<8 {
            // Generated grids aren't pixel-perfect. Use connected silhouettes so
            // a foot crossing an invisible cell boundary doesn't get sliced off.
            let region = regions[index]
            guard abs(region.midX - (CGFloat(index % 4) + 0.5) * CGFloat(w)) < CGFloat(w) * 0.42,
                  abs(region.midY - (CGFloat(index / 4) + 0.5) * CGFloat(h)) < CGFloat(h) * 0.30,
                  let cell = sheet.cropping(to: region) else { throw LikenessError.invalidSheet }
            guard let bounds = visibleBounds(cell), bounds.height > CGFloat(h) * 0.45,
                  bounds.width > CGFloat(w) * 0.12 else { throw LikenessError.invalidSheet }
            let request = VNDetectHumanBodyPoseRequest()
            try? VNImageRequestHandler(cgImage: cell).perform([request])
            let points = try? request.results?.first?.recognizedPoints(.all)
            let hips = [points?[.leftHip], points?[.rightHip]].compactMap { $0 }.filter { $0.confidence > 0.3 }
            let anchor = hips.count == 2 ? hips.map { $0.location.x * CGFloat(cell.width) }.reduce(0, +) / 2 : bounds.midX
            poses.append((cell, bounds, anchor))
        }
        // A shared scale and hip anchor prevent each pose growing/shrinking or
        // sliding sideways when an arm extends. Feet share the native Dock floor.
        let maxHeight = poses.map { $0.bounds.height }.max()!
        let maxHalfWidth = poses.map { max($0.anchor - $0.bounds.minX, $0.bounds.maxX - $0.anchor) }.max()!
        let scale = min(414 / maxHeight, 166 / maxHalfWidth)
        let frames = try poses.map { pose -> Data in
            guard let context = CutoutAnimation.context(width: 384, height: 512),
                  let cropped = pose.image.cropping(to: pose.bounds) else { throw LikenessError.invalidSheet }
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 192 - (pose.anchor - pose.bounds.minX) * scale,
                                             y: 512 * 0.06, width: pose.bounds.width * scale, height: pose.bounds.height * scale))
            guard let frame = context.makeImage(),
                  let data = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:]) else {
                throw LikenessError.invalidSheet
            }
            return data
        }
        return try GeneratedDance(frames: frames).validated()
    }

    private static func visibleBounds(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            for y in 0..<h {
                for x in 0..<w where buffer[(y * w + x) * 4 + 3] > 32 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func subjectRegions(_ image: CGImage) -> [CGRect] {
        // Bound analysis memory regardless of the image model's output resolution.
        let ratio = min(1, 1536 / Double(max(image.width, image.height)))
        let w = Int(Double(image.width) * ratio), h = Int(Double(image.height) * ratio)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        var mask = [UInt8](repeating: 0, count: w * h)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            for i in 0..<(w * h) { mask[i] = buffer[i * 4 + 3] > 64 ? 1 : 0 }
        }
        var regions: [CGRect] = []
        var queue: [Int] = []
        for start in mask.indices where mask[start] == 1 {
            queue.removeAll(keepingCapacity: true)
            queue.append(start); mask[start] = 0
            var cursor = 0, minX = w, minY = h, maxX = 0, maxY = 0
            while cursor < queue.count {
                let i = queue[cursor], x = i % w, y = i / w
                cursor += 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                        let next = ny * w + nx
                        if mask[next] == 1 { mask[next] = 0; queue.append(next) }
                    }
                }
            }
            guard queue.count > w * h / 100 else { continue }
            // Reject clipped figures and continuous opaque backgrounds.
            guard minX > 0, minY > 0, maxX < w - 1, maxY < h - 1 else { return [] }
            let rect = CGRect(x: Double(minX) / ratio, y: Double(minY) / ratio,
                              width: Double(maxX - minX + 1) / ratio, height: Double(maxY - minY + 1) / ratio)
            regions.append(rect.insetBy(dx: -2 / ratio, dy: -2 / ratio).integral
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)))
        }
        return regions.sorted {
            let row0 = Int($0.midY / (CGFloat(image.height) / 2)), row1 = Int($1.midY / (CGFloat(image.height) / 2))
            return row0 == row1 ? $0.midX < $1.midX : row0 < row1
        }
    }
}

final class GeneratedDanceFrames {
    static let shared = GeneratedDanceFrames()
    private let decoded = NSCache<NSString, CGImage>()
    private var versions: [String: UUID] = [:]

    init() {
        decoded.totalCostLimit = 64 * 1024 * 1024
        decoded.countLimit = 96
    }

    func invalidate(_ id: String) { versions[id] = UUID() }

    func frame(id: String, dance: GeneratedDance, beat: Double, duck: Int = 0) -> CGImage? {
        guard !dance.frames.isEmpty else { return nil }
        let loopBeats = dance.isVideo ? dance.duration * 2 : 2
        guard loopBeats.isFinite, loopBeats > 0 else { return nil }
        let phase = beat.isFinite ? (beat.truncatingRemainder(dividingBy: loopBeats) + loopBeats).truncatingRemainder(dividingBy: loopBeats) : 0
        let index = min(dance.frames.count - 1, Int(phase / loopBeats * Double(dance.frames.count)))
        if versions[id] == nil { versions[id] = UUID() }
        let key = "\(id):\(versions[id]!):\(index)" as NSString
        let frame: CGImage
        if let cached = decoded.object(forKey: key) { frame = cached }
        else {
            guard let image = GeneratedDance.decode(dance.frames[index]) else { return nil }
            decoded.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
            frame = image
        }
        guard duck > 0, let context = CutoutAnimation.context(width: 384, height: 512) else { return frame }
        let scale = 1 - Double(min(3, duck)) * 0.10
        context.draw(frame, in: CGRect(x: 0, y: 512 * 0.06 * (1 - scale), width: 384, height: 512 * scale))
        return context.makeImage()
    }
}
