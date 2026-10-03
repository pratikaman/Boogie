import AppKit
import AVFoundation
import CoreImage
import Vision

/// Imports continuous motion at 24 fps. One crop and scale for the whole clip
/// preserve the original movement, rather than recentering each pose separately.
enum VideoDance {
    static func load(_ url: URL, progress: @escaping (Double) -> Void = { _ in }) async throws -> GeneratedDance {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= 100_000_000 else { throw VideoDanceError.file }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration >= 1, duration <= 8.05 else { throw VideoDanceError.duration }
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              try await track.load(.nominalFrameRate) >= 20 else { throw VideoDanceError.frameRate }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 384, height: 512)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        defer { generator.cancelAllCGImageGeneration() }
        let count = min(192, Int(floor(duration * 24)))
        let context = CIContext(options: [.cacheIntermediates: false])
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .accurate
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let sequence = VNSequenceRequestHandler()
        var frames: [CGImage] = []
        var union = CGRect.null
        var canvas: CGSize?
        for index in 0..<count {
            try Task.checkCancellation()
            let sample = try await generator.image(at: CMTime(value: Int64(index), timescale: 24))
            let frame: CGImage = try autoreleasepool {
                let source = sample.image
                let stats = alpha(source)
                if stats.clearFraction > 0.1, !stats.bounds.isNull { return source }
                try sequence.perform([segmentation], on: source)
                guard let buffer = segmentation.results?.first?.pixelBuffer else { throw VideoDanceError.subject }
                let foreground = CIImage(cgImage: source)
                let mask = CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(
                    scaleX: CGFloat(source.width) / CGFloat(CVPixelBufferGetWidth(buffer)),
                    y: CGFloat(source.height) / CGFloat(CVPixelBufferGetHeight(buffer))))
                let cutout = foreground.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: foreground.extent),
                    kCIInputMaskImageKey: mask
                ])
                guard let result = context.createCGImage(cutout, from: foreground.extent) else { throw VideoDanceError.subject }
                return result
            }
            let bounds = alpha(frame).bounds
            guard !bounds.isNull, bounds.height >= CGFloat(frame.height) * 0.3 else { throw VideoDanceError.subject }
            let dimensions = CGSize(width: frame.width, height: frame.height)
            if let canvas, canvas != dimensions { throw VideoDanceError.file }
            canvas = dimensions
            union = union.union(bounds)
            frames.append(frame)
            progress(Double(index + 1) / Double(count) * 0.85)
        }
        let scale = min(320 / union.width, 414 / union.height)
        let target = CGRect(x: (384 - union.width * scale) / 2, y: 512 * 0.06,
                            width: union.width * scale, height: union.height * scale)
        var pngs: [Data] = []
        for (index, frame) in frames.enumerated() {
            try Task.checkCancellation()
            let png: Data = try autoreleasepool {
                guard let cropped = frame.cropping(to: union), let canvas = CutoutAnimation.context(width: 384, height: 512) else {
                    throw VideoDanceError.file
                }
                canvas.interpolationQuality = .high
                canvas.draw(cropped, in: target)
                guard let image = canvas.makeImage(),
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw VideoDanceError.file }
                return png
            }
            pngs.append(png)
            progress(0.85 + Double(index + 1) / Double(count) * 0.15)
        }
        return try GeneratedDance(frames: pngs, frameRate: 24).validated()
    }

    private static func alpha(_ image: CGImage) -> (bounds: CGRect, clearFraction: Double) {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1, clear = 0
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            for y in 0..<h { for x in 0..<w {
                if buffer[(y * w + x) * 4 + 3] > 24 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                } else { clear += 1 }
            }}
        }
        let bounds = maxX >= minX && maxY >= minY ? CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1) : .null
        return (bounds, Double(clear) / Double(w * h))
    }
}

enum VideoDanceError: LocalizedError {
    case file, duration, frameRate, subject
    var errorDescription: String? {
        switch self {
        case .file: return "Choose a local MP4 or MOV video smaller than 100 MB."
        case .duration: return "Choose a looping dance clip between 1 and 8 seconds long."
        case .frameRate: return "Choose a continuous video at 20 fps or higher. A slideshow cannot supply smooth motion."
        case .subject: return "Couldn’t isolate the dancer throughout this clip. Use one full-body person against a plain background, with a fixed camera."
        }
    }
}
