import Foundation
import CoreGraphics

// MARK: - Colours

struct RGBA: Equatable {
    var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 0

    init() {}
    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ hex: UInt32, alpha: Double = 1) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
        a = UInt8(max(0, min(255, (alpha * 255).rounded())))
    }
    static let clear = RGBA()
}

/// An outfit: hair + top + shorts + sneakers.
struct Fit {
    let id: String
    let name: String
    let hair: UInt32, hairLight: UInt32
    let top: UInt32, topShade: UInt32
    let shorts: UInt32
    let shoe: UInt32, sole: UInt32
}

struct Skin {
    let id: String
    let name: String
    let base: UInt32, blush: UInt32, mouth: UInt32
}

enum Wardrobe {
    static let fits: [Fit] = [
        Fit(id: "raver",  name: "Raver",  hair: 0xFF4FD8, hairLight: 0xFFA3EA, top: 0x00E5FF, topShade: 0x00B3CC, shorts: 0x1F2350, shoe: 0xFFFFFF, sole: 0xC9CBE0),
        Fit(id: "vapor",  name: "Vapor",  hair: 0xB388FF, hairLight: 0xDCC6FF, top: 0xFF80AB, topShade: 0xE0568A, shorts: 0x2B1B4F, shoe: 0xFFFFFF, sole: 0xCFC4E8),
        Fit(id: "lime",   name: "Lime",   hair: 0x1B1B1F, hairLight: 0x3D3D48, top: 0xC6FF00, topShade: 0x9ACC00, shorts: 0x101014, shoe: 0xC6FF00, sole: 0x2A2A30),
        Fit(id: "sunset", name: "Sunset", hair: 0xFF7A00, hairLight: 0xFFB35C, top: 0xFFD166, topShade: 0xE8B24A, shorts: 0x6A1B9A, shoe: 0xFFFFFF, sole: 0xE0D6EA),
        Fit(id: "ocean",  name: "Ocean",  hair: 0x2979FF, hairLight: 0x82B1FF, top: 0xF5F5F5, topShade: 0xD6D6D6, shorts: 0x0D2B6B, shoe: 0x2979FF, sole: 0xFFFFFF),
        Fit(id: "goth",   name: "Goth",   hair: 0x15151A, hairLight: 0x33333D, top: 0x2B2B33, topShade: 0x1D1D24, shorts: 0x15151A, shoe: 0x15151A, sole: 0x5A5A66),
    ]

    static let skins: [Skin] = [
        Skin(id: "porcelain", name: "Porcelain", base: 0xFFE3CC, blush: 0xFFB0BE, mouth: 0xC94A6A),
        Skin(id: "fair",      name: "Fair",      base: 0xF5CBA7, blush: 0xF39AA8, mouth: 0xB8405C),
        Skin(id: "tan",       name: "Tan",       base: 0xD9A066, blush: 0xD97A78, mouth: 0x9E3A4E),
        Skin(id: "brown",     name: "Brown",     base: 0xA5672E, blush: 0xB05A55, mouth: 0x7A2E3E),
        Skin(id: "deep",      name: "Deep",      base: 0x6B3E1E, blush: 0x8A4A45, mouth: 0x4E2230),
    ]

    static func fit(_ id: String) -> Fit { fits.first { $0.id == id } ?? fits[0] }
    static func skin(_ id: String) -> Skin { skins.first { $0.id == id } ?? skins[1] }
}

// MARK: - Pose

/// Elbow and hand positions relative to the shoulder, in sprite pixels.
/// Coordinates are given in the *left* arm's frame: negative x points away
/// from the body, positive y points down. The renderer mirrors the right arm.
struct Limb: Equatable {
    var ex: Int, ey: Int, hx: Int, hy: Int

    static let hang       = Limb(ex: -1, ey: 5, hx: -1, hy: 10)
    static let hangBack   = Limb(ex: -2, ey: 5, hx: -3, hy: 9)
    static let pumpLow    = Limb(ex: -4, ey: 4, hx: -1, hy: 6)
    static let pumpHigh   = Limb(ex: -4, ey: 4, hx: -1, hy: 2)
    static let up         = Limb(ex: -3, ey: -5, hx: -3, hy: -11)
    static let roofLow    = Limb(ex: -4, ey: -3, hx: -4, hy: -7)
    static let roofHigh   = Limb(ex: -3, ey: -6, hx: -3, hy: -11)
    static let pointUpOut = Limb(ex: -4, ey: -3, hx: -8, hy: -8)
    static let pointDownOut = Limb(ex: -3, ey: 3, hx: -6, hy: 8)
    static let crossDown  = Limb(ex: 1, ey: 4, hx: 5, hy: 8)
    static let robotUp    = Limb(ex: -5, ey: 0, hx: -5, hy: -5)
    static let robotDown  = Limb(ex: -5, ey: 0, hx: -5, hy: 5)
    static let hip        = Limb(ex: -4, ey: 4, hx: -1, hy: 7)
    static let tpose      = Limb(ex: -5, ey: 0, hx: -10, hy: 0)
    static let clapOut    = Limb(ex: -3, ey: 4, hx: 0, hy: 3)
    static let clapIn     = Limb(ex: -3, ey: 4, hx: 4, hy: 3)
    static let runFront   = Limb(ex: -2, ey: 4, hx: 1, hy: 1)
    static let runBack    = Limb(ex: -2, ey: 4, hx: -3, hy: 8)
    static let horns      = Limb(ex: -4, ey: -3, hx: -6, hy: -8)
    static let swingOut   = Limb(ex: -3, ey: 3, hx: -5, hy: 6)
    static let swingIn    = Limb(ex: -3, ey: 3, hx: 0, hy: 1)
}

/// Ankle offset (negative x = away from the body) and how far the foot is off the floor.
struct Leg: Equatable {
    var dx: Int = 0
    var lift: Int = 0
}

struct Pose: Equatable {
    var dx = 0, dy = 0             // whole-body offset; dy > 0 = crouch, dy < 0 = airborne/up
    var headDx = 0, headDy = 0     // extra head offset (tilt / bob)
    var airborne = false           // feet leave the floor with the body
    var lArm = Limb.hang, rArm = Limb.hang
    var lLeg = Leg(), rLeg = Leg()
    var eyesClosed = false

    func mirrored() -> Pose {
        var p = self
        p.dx = -dx
        p.headDx = -headDx
        swap(&p.lArm, &p.rArm)
        swap(&p.lLeg, &p.rLeg)
        return p
    }
}

// MARK: - Moves

struct MoveContext {
    /// Beats since the move started (continuous, never negative).
    let beat: Double
    init(beat: Double) { self.beat = max(0, beat) }
    /// 1 during the first half of every beat (body goes down on the beat), else 0.
    var bounce: Int { beat - floor(beat) < 0.5 ? 1 : 0 }
    var beatIndex: Int { Int(floor(beat)) }
    var eighth: Int { Int(floor(beat * 2)) }
    func wave(period: Double, amplitude: Double) -> Int {
        Int((amplitude * sin(2 * .pi * beat / period)).rounded())
    }
}

struct Move {
    let id: String
    let name: String
    let pose: (MoveContext) -> Pose
}

enum Moves {
    static let bop = Move(id: "bop", name: "Bop") { c in
        var p = Pose()
        p.dy = c.bounce
        p.lArm = c.bounce == 1 ? .pumpLow : .pumpHigh
        p.rArm = p.lArm
        p.headDx = (c.beatIndex / 2) % 2 == 0 ? -1 : 1
        return p
    }

    static let roof = Move(id: "roof", name: "Raise the roof") { c in
        var p = Pose()
        p.dy = c.bounce
        p.lArm = c.bounce == 1 ? .roofLow : .roofHigh
        p.rArm = p.lArm
        p.headDy = c.bounce == 1 ? 0 : -1
        return p
    }

    static let sway = Move(id: "sway", name: "Sway") { c in
        var p = Pose()
        p.dx = c.wave(period: 4, amplitude: 3)
        let lean = p.dx.signum()
        let shift = -2 * lean
        p.lArm = Limb(ex: -3, ey: -5, hx: -3 + shift, hy: -11)
        p.rArm = Limb(ex: -3, ey: -5, hx: -3 - shift, hy: -11)
        p.dy = c.bounce
        // feet stay planted wide while the hips travel
        p.lLeg = Leg(dx: -2 - p.dx)
        p.rLeg = Leg(dx: -2 + p.dx)
        return p
    }

    static let disco = Move(id: "disco", name: "Disco") { c in
        var p = Pose()
        let up = c.beatIndex % 2 == 0
        p.rArm = up ? .pointUpOut : .crossDown
        p.lArm = .hip
        p.dx = up ? 1 : -1
        p.dy = c.bounce
        p.headDx = up ? 1 : 0
        p.lLeg = Leg(dx: -2 - p.dx)
        p.rLeg = Leg(dx: -2 + p.dx)
        return p
    }

    static let robot = Move(id: "robot", name: "Robot") { c in
        var p = Pose()
        let a = c.eighth % 2 == 0
        p.lArm = a ? .robotUp : .robotDown
        p.rArm = a ? .robotDown : .robotUp
        p.headDx = c.beatIndex % 2 == 0 ? -1 : 1
        return p
    }

    static let runningMan = Move(id: "running", name: "Running man") { c in
        var p = Pose()
        let left = c.beatIndex % 2 == 0
        let lifted = Leg(dx: -1, lift: 3)
        p.lLeg = left ? lifted : Leg()
        p.rLeg = left ? Leg() : lifted
        p.lArm = left ? .runBack : .runFront
        p.rArm = left ? .runFront : .runBack
        p.dy = c.bounce == 1 ? 0 : 1
        return p
    }

    static let twist = Move(id: "twist", name: "Twist") { c in
        var p = Pose()
        let dir = c.eighth % 2 == 0 ? -1 : 1
        p.dx = dir
        p.headDx = -dir
        p.lLeg = Leg(dx: -dir)
        p.rLeg = Leg(dx: dir)
        p.lArm = dir == -1 ? .swingOut : .swingIn
        p.rArm = dir == -1 ? .swingIn : .swingOut
        return p
    }

    static let pogo = Move(id: "pogo", name: "Pogo") { c in
        var p = Pose()
        let t = c.beat - 2 * floor(c.beat / 2)
        if t < 1 {
            p.dy = 1
            p.lArm = .hangBack; p.rArm = .hangBack
        } else if t < 1.5 {
            p.dy = -4; p.airborne = true
            p.lArm = .up; p.rArm = .up
            p.lLeg = Leg(dx: -1, lift: 0); p.rLeg = Leg(dx: -1, lift: 0)
        } else {
            p.dy = -2; p.airborne = true
            p.lArm = .roofHigh; p.rArm = .roofHigh
        }
        return p
    }

    static let stepTouch = Move(id: "step", name: "Step touch") { c in
        var p = Pose()
        let step = c.eighth % 8
        p.dx = [-2, -4, -4, -2, 2, 4, 4, 2][step]
        if step == 0 { p.lLeg = Leg(dx: -2) }
        if step == 4 { p.rLeg = Leg(dx: -2) }
        let clap = step == 1 || step == 5
        p.lArm = clap ? .clapIn : .clapOut
        p.rArm = p.lArm
        p.dy = c.bounce
        return p
    }

    static let wave = Move(id: "wave", name: "Wave") { c in
        var p = Pose()
        let w = c.wave(period: 1, amplitude: 2)
        p.lArm = .hip
        p.rArm = Limb(ex: -3, ey: -5, hx: -3 + w, hy: -11)
        p.dy = c.bounce
        p.headDx = w > 0 ? 1 : 0
        return p
    }

    static let headbang = Move(id: "headbang", name: "Headbang") { c in
        var p = Pose()
        p.headDy = c.bounce == 1 ? 2 : 0
        p.dy = c.bounce
        p.lArm = .horns; p.rArm = .horns
        return p
    }

    /// Paused: stand there, breathe, blink.
    static let idle = Move(id: "idle", name: "Chilling") { c in
        var p = Pose()
        p.headDy = sin(2 * .pi * c.beat / 4) > 0.6 ? -1 : 0
        return p
    }

    /// Sliding along the Dock because the MacBook is tilted. `dir` is absolute (screen left/right).
    static func surf(dir: Int) -> Pose {
        var p = Pose()
        p.dy = 1
        p.lArm = .pointUpOut
        p.rArm = .tpose
        p.lLeg = Leg(dx: -3); p.rLeg = Leg(dx: -3)
        p.headDx = -1
        return dir > 0 ? p.mirrored() : p
    }

    /// The lid is coming down: brace, crouch, flatten.
    static func duck(stage: Int) -> Pose {
        var p = Pose()
        switch stage {
        case 1:
            p.lArm = .roofHigh; p.rArm = .roofHigh
            p.headDy = -1
        case 2:
            p.dy = 2
            p.lArm = .roofLow; p.rArm = .roofLow
        default:
            p.dy = 3
            p.lArm = .tpose; p.rArm = .tpose
            p.lLeg = Leg(dx: -2); p.rLeg = Leg(dx: -2)
        }
        return p
    }

    static let all: [Move] = [bop, roof, sway, disco, robot, runningMan, twist, pogo, stepTouch, wave, headbang]

    static func named(_ id: String) -> Move? { all.first { $0.id == id } }
}

// MARK: - Pixel canvas

struct PixelCanvas {
    static let width = 36
    static let height = 36

    private(set) var px: [RGBA] = Array(repeating: .clear, count: width * height)

    mutating func clear() {
        for i in px.indices { px[i] = .clear }
    }

    mutating func put(_ x: Int, _ y: Int, _ c: RGBA) {
        guard x >= 0, x < Self.width, y >= 0, y < Self.height, c.a > 0 else { return }
        let i = y * Self.width + x
        if c.a == 255 { px[i] = c; return }
        let d = px[i]
        let sa = Double(c.a) / 255, da = Double(d.a) / 255
        let oa = sa + da * (1 - sa)
        func mix(_ s: UInt8, _ t: UInt8) -> UInt8 {
            oa == 0 ? 0 : UInt8(((Double(s) * sa + Double(t) * da * (1 - sa)) / oa).rounded())
        }
        px[i] = RGBA(r: mix(c.r, d.r), g: mix(c.g, d.g), b: mix(c.b, d.b), a: UInt8((oa * 255).rounded()))
    }

    /// Two-pixel-thick line. `brush` picks which side the second pixel goes on
    /// for steep segments (+1 = right, -1 = left); shallow segments thicken downwards.
    mutating func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, brush: Int, _ c: RGBA) {
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        let steep = -dy >= dx
        var err = dx + dy
        var x = x0, y = y0
        while true {
            put(x, y, c)
            if steep { put(x + brush, y, c) } else { put(x, y + 1, c) }
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    mutating func blit(_ rows: [String], x: Int, y: Int, _ color: (Character) -> RGBA?) {
        for (j, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() {
                if let c = color(ch) { put(x + i, y + j, c) }
            }
        }
    }

    func cgImage() -> CGImage? {
        let w = Self.width, h = Self.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let p = px[i]
            let a = Int(p.a)
            bytes[i * 4] = UInt8(Int(p.r) * a / 255)
            bytes[i * 4 + 1] = UInt8(Int(p.g) * a / 255)
            bytes[i * 4 + 2] = UInt8(Int(p.b) * a / 255)
            bytes[i * 4 + 3] = p.a
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - Particles

struct Heart {
    var x: Double, y: Double
    var vx: Double, vy: Double
    var age: Double = 0
    var life: Double
    var color: UInt32
}

/// Club lights state passed to the renderer.
struct StageFX {
    var lights = false
    var beat: Double = 0
    static let none = StageFX()
}

// MARK: - Renderer

/// Draws the dancer into a PixelCanvas. The body is a hand-drawn bitmap, the
/// limbs are procedural 2px lines so every move can pose them freely.
final class SpriteRenderer {
    var fit: Fit
    var skin: Skin

    init(fit: Fit, skin: Skin) { self.fit = fit; self.skin = skin }

    // 10px wide, rows 3...15 of the sprite (hair, face, neck).
    private static func headRows(eyesClosed: Bool) -> [String] {
        [
            "...HHHH...",
            "..HLLHHH..",
            ".HLHHHHHH.",
            "HHHHHHHHHH",
            "HHHSSSSHHH",
            "HHSSSSSSHH",
            "HSSSSSSSSH",
            eyesClosed ? "HSSSSSSSSH" : "HSEWSSEWSH",
            eyesClosed ? "HSEESSEESH" : "HSEESSEESH",
            ".BSSSSSSB.",
            ".SSSMMSSS.",
            "..SSSSSS..",
            "....SS....",
        ]
    }

    // 10px wide, rows 16...24 (crop top, midriff, shorts).
    private static let torsoRows = [
        ".TTTTTTTT.",
        "TTTTTTTTTT",
        "TTTTTTTTTT",
        ".DDDDDDDD.",
        "..SSSSSS..",
        "..SSSSSS..",
        ".PPPPPPPP.",
        ".PPPPPPPP.",
        ".PPP..PPP.",
    ]

    private static let bunRows = [
        ".HH.",
        "HLHH",
        "HHHH",
        ".HH.",
    ]

    private static let heartRows = [
        ".X.X.",
        "XXXXX",
        ".XXX.",
        "..X..",
    ]

    private func color(_ ch: Character) -> RGBA? {
        switch ch {
        case "H": return RGBA(fit.hair)
        case "L": return RGBA(fit.hairLight)
        case "S": return RGBA(skin.base)
        case "E": return RGBA(0x1B1B24)
        case "W": return RGBA(0xFFFFFF)
        case "B": return RGBA(skin.blush)
        case "M": return RGBA(skin.mouth)
        case "T": return RGBA(fit.top)
        case "D": return RGBA(fit.topShade)
        case "P": return RGBA(fit.shorts)
        default: return nil
        }
    }

    func draw(_ p: Pose, bunLag: Int, hearts: [Heart], into c: inout PixelCanvas, fx: StageFX = .none) {
        let dx = p.dx, dy = p.dy
        let skinC = RGBA(skin.base)

        if fx.lights { drawLights(fx, dx: dx, into: &c) }

        // Shadow on the floor (does not move with dy; shrinks in the air).
        let inset = p.airborne ? min(3, max(1, (-dy + 1) / 2)) : 0
        let shade = p.airborne ? 0.14 : 0.26
        for x in (12 + dx + inset)...(23 + dx - inset) { c.put(x, 32, RGBA(0x000000, alpha: shade)) }
        for x in (14 + dx + inset)...(21 + dx - inset) { c.put(x, 33, RGBA(0x000000, alpha: shade * 0.55)) }

        // Legs + sneakers.
        let floorY = 30 + (p.airborne ? dy : 0)
        func leg(hipX: Int, sign: Int, brush: Int, _ leg: Leg) {
            let hipY = 25 + dy
            let shoeTop = max(hipY + 1, floorY - min(leg.lift, 3))
            let ankleX = hipX + sign * leg.dx
            c.line(hipX, hipY, ankleX, shoeTop - 1, brush: brush, skinC)
            for x in (ankleX - 1)...(ankleX + 1) {
                c.put(x, shoeTop, RGBA(fit.shoe))
                c.put(x, shoeTop + 1, RGBA(fit.sole))
            }
        }
        leg(hipX: 15, sign: 1, brush: 1, p.lLeg)
        leg(hipX: 20, sign: -1, brush: -1, p.rLeg)

        // Torso, head, buns.
        c.blit(Self.torsoRows, x: 13 + dx, y: 16 + dy, color)
        let hx = 13 + dx + p.headDx, hy = 3 + dy + p.headDy
        c.blit(Self.headRows(eyesClosed: p.eyesClosed), x: hx, y: hy, color)
        let lag = max(-1, min(1, bunLag))
        c.blit(Self.bunRows, x: hx - 2, y: hy - 1 + lag, color)
        c.blit(Self.bunRows, x: hx + 8, y: hy - 1 + lag, color)

        // Arms (drawn last so hands pass in front of the body).
        func arm(shoulderX: Int, sign: Int, brush: Int, _ l: Limb) {
            let sy = 16 + dy
            let ex = shoulderX + sign * l.ex, ey = sy + l.ey
            let hx = shoulderX + sign * l.hx, hy = sy + l.hy
            c.line(shoulderX, sy, ex, ey, brush: brush, skinC)
            c.line(ex, ey, hx, hy, brush: brush, skinC)
            let rows = l.hy < l.ey ? [hy - 1, hy] : [hy, hy + 1]
            let handC = fx.lights ? RGBA(sign > 0 ? 0xFF2E9A : 0x00E5FF) : skinC
            for y in rows { c.put(hx, y, handC); c.put(hx + brush, y, handC) }
            if fx.lights {
                // glow sticks: a soft halo around each hand
                let lo = min(hx, hx + brush), hi = max(hx, hx + brush)
                let halo = RGBA(sign > 0 ? 0xFF2E9A : 0x00E5FF, alpha: 0.35)
                for y in rows { c.put(lo - 1, y, halo); c.put(hi + 1, y, halo) }
                for x in lo...hi { c.put(x, rows[0] - 1, halo); c.put(x, rows[1] + 1, halo) }
            }
        }
        arm(shoulderX: 12, sign: 1, brush: 1, p.lArm)
        arm(shoulderX: 23, sign: -1, brush: -1, p.rArm)

        // Hearts.
        for h in hearts {
            let alpha = max(0, 1 - h.age / h.life)
            let col = RGBA(h.color, alpha: alpha)
            c.blit(Self.heartRows, x: Int(h.x.rounded()), y: Int(h.y.rounded())) { $0 == "X" ? col : nil }
        }
    }

    private static let lightColors: [UInt32] = [0xFF2E9A, 0x00E5FF, 0x8B5CF6, 0xC6FF00]

    /// Spotlight cone, floor glow and a mirror ball. Colour changes every beat.
    private func drawLights(_ fx: StageFX, dx: Int, into c: inout PixelCanvas) {
        let col = Self.lightColors[Int(floor(max(0, fx.beat))) & 3]
        let cx = 17.5 + Double(dx)
        for y in 3...31 {
            let t = Double(y - 3) / 28
            let half = 2.0 + t * 14
            let lo = Int((cx - half).rounded()), hi = Int((cx + half).rounded())
            for x in lo...hi {
                let edge = abs(Double(x) - cx) / half
                let a = 0.20 * (1 - edge * 0.7) * (0.6 + 0.4 * (1 - t))
                c.put(x, y, RGBA(col, alpha: a))
            }
        }
        for (y, w, a) in [(32, 12, 0.35), (33, 11, 0.28), (34, 9, 0.20), (35, 6, 0.12)] {
            for x in (18 - w + dx)...(17 + w + dx) { c.put(x, y, RGBA(col, alpha: a)) }
        }
        let spin = Int(floor(max(0, fx.beat) * 2)) & 1
        let white = RGBA(0xFFFFFF), grey = RGBA(0xB8BCD0)
        let ball = spin == 0 ? [".W.", "WGW", ".W."] : [".G.", "GWG", ".G."]
        c.blit(ball, x: 16, y: 0) { $0 == "W" ? white : ($0 == "G" ? grey : nil) }
        let spots = [(13, 1), (21, 2), (14, 4), (20, 0)]
        let spot = spots[Int(floor(max(0, fx.beat) * 4)) & 3]
        c.put(spot.0, spot.1, RGBA(0xFFFFFF, alpha: 0.9))
    }
}
