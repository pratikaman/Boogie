import AppKit
import Combine
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

enum CutoutMotion: String, Codable, CaseIterable, Identifiable {
    case bounce, sway, twirl
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

struct CustomDancer: Codable, Identifiable {
    let id: String
    var name: String
    var motion: CutoutMotion
    let png: Data
    var avatar: AvatarDesign? = nil
    var generatedDance: GeneratedDance? = nil
    var isAnimated: Bool { avatar != nil || generatedDance != nil }
    var motionName: String {
        if let generatedDance { return generatedDance.isVideo ? "Video dance" : "Photo groove" }
        return avatar == nil ? motion.name : motion.danceName
    }
}

/// Each dancer is one atomic document, independent of the imported source file.
/// Only bounded, normalized PNGs are persisted; source photos are never copied.
final class CustomDancerStore: ObservableObject {
    static var shared = CustomDancerStore()
    @Published private(set) var dancers: [CustomDancer] = []
    private let root: URL
    private let images = NSCache<NSString, CGImage>()

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Boogie/Custom Dancers", isDirectory: true)
        images.totalCostLimit = 16 * 1024 * 1024
        let files = (try? FileManager.default.contentsOfDirectory(at: self.root, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for file in files where file.pathExtension == "json" {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 70_000_000,
                  let data = try? Data(contentsOf: file),
                  let dancer = try? JSONDecoder().decode(CustomDancer.self, from: data),
                  Self.validID(dancer.id), file.deletingPathExtension().lastPathComponent == dancer.id,
                  !dancer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  dancer.name.count <= 32, Self.decode(dancer.png) != nil,
                  dancer.avatar.map({ (try? $0.validated()) != nil }) ?? true,
                  dancer.generatedDance.map({ (try? $0.validated()) != nil }) ?? true,
                  !(dancer.avatar != nil && dancer.generatedDance != nil) else { continue }
            dancers.append(dancer)
        }
        sort()
    }

    func find(_ id: String) -> CustomDancer? { dancers.first { $0.id == id } }

    func image(_ id: String) -> CGImage? {
        if let image = images.object(forKey: id as NSString) { return image }
        guard let dancer = find(id), let image = Self.decode(dancer.png) else { return nil }
        images.setObject(image, forKey: id as NSString, cost: image.bytesPerRow * image.height)
        return image
    }

    func frame(_ id: String, beat: Double, duck: Int = 0) -> CGImage? {
        guard let dancer = find(id) else { return nil }
        if let dance = dancer.generatedDance {
            return GeneratedDanceFrames.shared.frame(id: id, dance: dance, beat: beat, duck: duck)
        }
        if let avatar = dancer.avatar {
            return AvatarFrames.shared.frame(id: id, design: avatar, motion: dancer.motion, beat: beat, duck: duck)
        }
        guard let image = image(id) else { return nil }
        return CutoutAnimation.frame(image: image, motion: dancer.motion, beat: beat, duck: duck)
    }

    @discardableResult
    func save(id: String? = nil, name: String, motion: CutoutMotion, image: CGImage, avatar: AvatarDesign? = nil, generatedDance: GeneratedDance? = nil) throws -> CustomDancer {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 32 else { throw CreatorError.name }
        if let id, find(id) == nil { throw CreatorError.missing }
        _ = try avatar?.validated()
        _ = try generatedDance?.validated()
        guard avatar == nil || generatedDance == nil else { throw LikenessError.invalidSheet }
        let normalized = (avatar != nil || generatedDance != nil) && image.width == 384 && image.height == 512 ? image : try PhotoImport.normalize(image)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CreatorError.image
        }
        CGImageDestinationAddImage(destination, normalized, nil)
        guard CGImageDestinationFinalize(destination) else { throw CreatorError.image }
        let dancer = CustomDancer(id: id ?? "custom-\(UUID().uuidString.lowercased())", name: name, motion: motion, png: data as Data, avatar: avatar, generatedDance: generatedDance)
        try write(dancer)
        images.removeObject(forKey: dancer.id as NSString)
        AvatarFrames.shared.invalidate(dancer.id)
        GeneratedDanceFrames.shared.invalidate(dancer.id)
        return dancer
    }

    func setMotion(_ motion: CutoutMotion, for id: String) throws {
        guard var dancer = find(id) else { throw CreatorError.missing }
        dancer.motion = motion
        try write(dancer)
    }

    func remove(_ id: String) throws {
        guard find(id) != nil else { throw CreatorError.missing }
        try FileManager.default.removeItem(at: root.appendingPathComponent(id).appendingPathExtension("json"))
        dancers.removeAll { $0.id == id }
        images.removeObject(forKey: id as NSString)
        AvatarFrames.shared.invalidate(id)
        GeneratedDanceFrames.shared.invalidate(id)
    }

    private func write(_ dancer: CustomDancer) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(dancer).write(to: root.appendingPathComponent(dancer.id).appendingPathExtension("json"), options: .atomic)
        dancers.removeAll { $0.id == dancer.id }
        dancers.append(dancer)
        sort()
    }

    private func sort() { dancers.sort { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    private static func validID(_ id: String) -> Bool {
        id.hasPrefix("custom-") && UUID(uuidString: String(id.dropFirst(7))) != nil
    }
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == 384,
              properties[kCGImagePropertyPixelHeight] as? Int == 512 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

enum CreatorError: LocalizedError {
    case image, tooLarge, empty, name, missing, noSubject, unavailable, cutoutFailed
    var errorDescription: String? {
        switch self {
        case .image: return "This image couldn’t be opened. Try a PNG, JPEG, or HEIC photo."
        case .tooLarge: return "Choose an image smaller than 30 MB and 100 megapixels."
        case .empty: return "This image is completely transparent. Choose an image with a visible subject."
        case .name: return "Give your dancer a name between 1 and 32 characters."
        case .missing: return "This dancer is no longer in your collection."
        case .noSubject: return "No clear subject was found. Try another photo, or keep the original background."
        case .unavailable: return "Background removal needs macOS 14 or later. You can still import a transparent PNG."
        case .cutoutFailed: return "Background removal couldn’t finish on this Mac. Keep the original background, or try a transparent PNG."
        }
    }
}

enum PhotoImport {
    static var supportsCutout: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    /// ImageIO downsamples before decoding and applies EXIF rotation.
    static func load(_ url: URL) throws -> CGImage {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL else { throw CreatorError.image }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw CreatorError.image }
        guard let size = values.fileSize, size <= 30_000_000 else { throw CreatorError.tooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double else { throw CreatorError.image }
        guard width > 0, height > 0, width * height <= 100_000_000 else { throw CreatorError.tooLarge }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw CreatorError.image }
        return image
    }

    static func removeBackground(_ image: CGImage, cropped: Bool = true) throws -> CGImage {
        guard #available(macOS 14.0, *) else { throw CreatorError.unavailable }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do { try handler.perform([request]) }
        catch { throw CreatorError.cutoutFailed }
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw CreatorError.noSubject }
        let buffer: CVPixelBuffer
        do { buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: cropped) }
        catch { throw CreatorError.cutoutFailed }
        let cutout = CIImage(cvPixelBuffer: buffer)
        guard let output = CIContext().createCGImage(cutout, from: cutout.extent) else { throw CreatorError.image }
        return output
    }

    /// Trim transparent margins, then fit above the same floor used by native windows.
    static func normalize(_ image: CGImage) throws -> CGImage {
        guard image.width <= 4096, image.height <= 4096 else { throw CreatorError.tooLarge }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var trimmed: CGImage?
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 8 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            if maxX >= minX, maxY >= minY {
                trimmed = context.makeImage()?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
            }
        }
        guard let trimmed else { throw CreatorError.empty }
        guard let context = CutoutAnimation.context(width: 384, height: 512) else { throw CreatorError.image }
        let ratio = min(268.0 / Double(trimmed.width), 374.0 / Double(trimmed.height))
        let w = Double(trimmed.width) * ratio, h = Double(trimmed.height) * ratio
        context.interpolationQuality = .high
        context.draw(trimmed, in: CGRect(x: (384 - w) / 2, y: 512 * 0.06, width: w, height: h))
        guard let output = context.makeImage() else { throw CreatorError.image }
        return output
    }
}

/// One motion function drives both the creator preview and native dancer layers.
enum CutoutAnimation {
    static func transform(motion: CutoutMotion, beat: Double, size: CGSize, duck: Int = 0) -> CGAffineTransform {
        let phase = (beat.isFinite ? beat : 0) * .pi
        let bob = abs(sin(phase))
        var x = 0.0, y = 0.0, angle = 0.0, scaleX = 1.0, scaleY = 1.0
        switch motion {
        case .bounce:
            y = bob * size.height * 0.065
            angle = sin(phase) * 0.035
            scaleY = 1 - (1 - bob) * 0.04
        case .sway:
            x = sin(phase / 2) * size.width * 0.06
            angle = sin(phase / 2) * 0.10
            y = bob * size.height * 0.018
        case .twirl:
            scaleX = cos(phase / 2)
            if abs(scaleX) < 0.05 { scaleX = scaleX < 0 ? -0.05 : 0.05 }
            y = bob * size.height * 0.045
        }
        if duck > 0 { y = 0; angle = 0; scaleY = 1 - Double(min(3, duck)) * 0.14 }
        return CGAffineTransform(translationX: x, y: y).rotated(by: angle).scaledBy(x: scaleX, y: scaleY)
    }

    static func frame(image: CGImage, motion: CutoutMotion, beat: Double, duck: Int = 0) -> CGImage? {
        let size = CGSize(width: 384, height: 512)
        guard let context = context(width: 384, height: 512) else { return nil }
        context.translateBy(x: size.width / 2, y: size.height * 0.06)
        context.concatenate(transform(motion: motion, beat: beat, size: size, duck: duck))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: -size.width / 2, y: -size.height * 0.06, width: size.width, height: size.height))
        return context.makeImage()
    }

    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
