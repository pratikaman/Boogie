// Renders the sprite to PNG/GIF files. Used by build.sh for the app icon and
// by hand for README previews. Usage: render <outdir> [sheet|icon|gif|all]
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "."
let what = args.count > 2 ? args[2] : "all"
let bg = CGColor(red: 0x0E / 255.0, green: 0x11 / 255.0, blue: 0x16 / 255.0, alpha: 1)

func context(w: Int, h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    return ctx
}

func frame(_ renderer: SpriteRenderer, _ pose: Pose, bunLag: Int = 0, hearts: [Heart] = [], fx: StageFX = .none) -> CGImage {
    var canvas = PixelCanvas()
    renderer.draw(pose, bunLag: bunLag, hearts: hearts, into: &canvas, fx: fx)
    return canvas.cgImage()!
}

// Sensor crossover frames: surf left/right, the three duck stages, club lights.
func fxSheet() {
    let scale = 5
    let renderer = SpriteRenderer(fit: Wardrobe.fits[0], skin: Wardrobe.skins[1])
    var frames: [(Pose, StageFX)] = [(Moves.surf(dir: -1), .none), (Moves.surf(dir: 1), .none)]
    for stage in 1...3 { frames.append((Moves.duck(stage: stage), .none)) }
    for i in 0..<4 {
        let b = Double(i) * 0.5 + 0.1
        frames.append((Moves.bop.pose(MoveContext(beat: b)), StageFX(lights: true, beat: b)))
    }
    let ctx = context(w: frames.count * S * scale, h: S * scale)
    ctx.setFillColor(bg)
    ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    for (i, f) in frames.enumerated() {
        ctx.draw(frame(renderer, f.0, fx: f.1), in: CGRect(x: i * S * scale, y: 0, width: S * scale, height: S * scale))
    }
    write(ctx.makeImage()!, "fx.png")
}

func write(_ img: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

let S = PixelCanvas.width

// Sprite sheet: every move × 8 eighth-notes, each fit on its own row band.
func sheet() {
    let scale = 5
    let cols = 8, rows = Moves.all.count
    let ctx = context(w: cols * S * scale, h: rows * S * scale)
    ctx.setFillColor(bg)
    ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    for (r, move) in Moves.all.enumerated() {
        let renderer = SpriteRenderer(fit: Wardrobe.fits[r % Wardrobe.fits.count], skin: Wardrobe.skins[r % Wardrobe.skins.count])
        for col in 0..<cols {
            let b = Double(col) * 0.5 + 0.1
            let pose = move.pose(MoveContext(beat: b))
            let prev = move.pose(MoveContext(beat: b - 0.2))
            let lag = max(-2, min(2, (prev.dy + prev.headDy) - (pose.dy + pose.headDy)))
            let img = frame(renderer, pose, bunLag: lag)
            let y = ctx.height - (r + 1) * S * scale
            ctx.draw(img, in: CGRect(x: col * S * scale, y: y, width: S * scale, height: S * scale))
        }
    }
    write(ctx.makeImage()!, "sheet.png")
}

// Icon: rounded dark tile with the dancer mid-disco.
func icon() {
    let size = 1024
    let ctx = context(w: size, h: size)
    let radius = CGFloat(size) * 0.22
    let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(bg)
    ctx.fillPath()
    let renderer = SpriteRenderer(fit: Wardrobe.fits[0], skin: Wardrobe.skins[1])
    var pose = Moves.disco.pose(MoveContext(beat: 0.1))
    pose.dx = 0
    let hearts = [Heart(x: 6, y: 6, vx: 0, vy: 0, age: 0, life: 1, color: 0xFF4F8B),
                  Heart(x: 27, y: 11, vx: 0, vy: 0, age: 0.3, life: 1, color: 0xFF7AB8)]
    let img = frame(renderer, pose, hearts: hearts)
    let scale = 26
    let px = S * scale
    ctx.draw(img, in: CGRect(x: (size - px) / 2, y: (size - px) / 2 - 20, width: px, height: px))
    write(ctx.makeImage()!, "icon.png")
}

// GIF: cycles through every move, 4 beats each at 120 BPM, 15 fps.
func gif() {
    let scale = 4
    let fps = 15.0, bpm = 120.0
    let beatsPerMove = 4.0
    let secondsPerMove = beatsPerMove * 60 / bpm
    let total = Int(secondsPerMove * fps) * Moves.all.count
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("boogie.gif")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, total, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let renderer = SpriteRenderer(fit: Wardrobe.fits[0], skin: Wardrobe.skins[1])
    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
    for (m, move) in Moves.all.enumerated() {
        let n = Int(secondsPerMove * fps)
        for i in 0..<n {
            let t = Double(i) / fps
            let b = t * bpm / 60
            let pose = move.pose(MoveContext(beat: b))
            let prev = move.pose(MoveContext(beat: b - 0.16))
            let lag = max(-2, min(2, (prev.dy + prev.headDy) - (pose.dy + pose.headDy)))
            let img = frame(renderer, pose, bunLag: lag)
            let ctx = context(w: S * scale, h: S * scale)
            ctx.setFillColor(bg)
            ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: S * scale, height: S * scale))
            CGImageDestinationAddImage(dest, ctx.makeImage()!, frameProps)
        }
        _ = m
    }
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

switch what {
case "fx": fxSheet()
case "sheet": sheet()
case "icon": icon()
case "gif": gif()
default: sheet(); icon(); gif()
}
