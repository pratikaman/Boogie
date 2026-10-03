import AppKit

/// The transparent, always-on-top panel one dancer lives in.
final class DancerWindow: NSPanel {
    let dancer: DancerView

    init(index: Int, characterID: String, renderer: SpriteRenderer, scale: Int) {
        let rect = NSRect(origin: .zero, size: Companions.size(for: characterID, scale: scale))
        dancer = DancerView(index: index, characterID: characterID, renderer: renderer, frame: rect)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        // Set last: NSPanel's isFloatingPanel and friends reset the level.
        level = .statusBar                      // above normal windows and the Dock
        isMovableByWindowBackground = false     // we handle drag vs. click ourselves
        isReleasedWhenClosed = false
        contentView = dancer
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Plays rendered people or procedural pixel sprites and handles
/// click (celebrate), drag (move), and right-click (controls).
final class DancerView: NSView {
    let index: Int
    var renderer: SpriteRenderer
    let characterID: String
    private let playback = CompanionPlayback()
    private let personLayer = CALayer()
    private let effectsLayer = CALayer()
    private var currentImage: CGImage?

    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?
    var onGrab: (() -> Void)?

    /// Set by the app while gravity has her: falling, or just landed.
    enum Motion { case none, falling(since: TimeInterval), landing(since: TimeInterval) }
    var motion: Motion = .none

    private var canvas = PixelCanvas()
    private var hearts: [Heart] = []
    private var specialStart: TimeInterval?
    private var nextBlink: TimeInterval = 0
    private var blinkStart: TimeInterval?
    private var lastTick: TimeInterval = 0

    private var dragOrigin: CGPoint?
    private var windowOrigin: CGPoint = .zero
    private var dragged = false

    /// Odd-numbered dancers mirror every move so a squad looks choreographed.
    var mirrored: Bool { index % 2 == 1 }

    init(index: Int, characterID: String, renderer: SpriteRenderer, frame: NSRect) {
        self.characterID = characterID
        self.index = index
        self.renderer = renderer
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        layer?.contentsGravity = .resize
        layer?.backgroundColor = .clear
        if Companions.find(characterID).realistic {
            personLayer.frame = bounds
            personLayer.contentsGravity = .resize
            personLayer.magnificationFilter = .linear
            personLayer.minificationFilter = .linear
            layer?.addSublayer(personLayer)
            effectsLayer.frame = bounds
            layer?.addSublayer(effectsLayer)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Animation

    func tick(now: TimeInterval, choreo: Choreographer, ambience: Ambience = Ambience()) {
        if let s = specialStart, now - s >= 0.9 { specialStart = nil }
        if case .landing(let s) = motion, now - s >= Moves.landDuration { motion = .none }

        var pose = fullPose(at: now, choreo, ambience)
        let prev = fullPose(at: now - 0.08, choreo, ambience)
        let bunLag = (prev.dy + prev.headDy) - (pose.dy + pose.headDy)

        // Blink every few seconds.
        if nextBlink == 0 { nextBlink = now + Double.random(in: 2...5) }
        if let b = blinkStart {
            if now - b > 0.13 { blinkStart = nil; nextBlink = now + Double.random(in: 2...6) }
        } else if now >= nextBlink {
            blinkStart = now
        }
        pose.eyesClosed = blinkStart != nil

        // Float the hearts.
        let dt = lastTick == 0 ? 0 : min(0.1, now - lastTick)
        lastTick = now
        hearts = hearts.compactMap { h in
            var h = h
            h.age += dt
            h.x += h.vx * dt
            h.y += h.vy * dt
            return h.age < h.life ? h : nil
        }

        if Companions.find(characterID).realistic {
            renderPerson(now: now, choreo: choreo, ambience: ambience)
            return
        }
        canvas.clear()
        renderer.draw(pose, bunLag: bunLag, hearts: hearts, into: &canvas,
                      fx: StageFX(lights: ambience.lights, beat: choreo.beat(now: now)))
        currentImage = canvas.cgImage()
        layer?.contents = currentImage
        updateMousePassthrough()
    }

    private func renderPerson(now: TimeInterval, choreo: Choreographer, ambience: Ambience) {
        let frame = playback.frame(id: characterID, sample: choreo.dance(now: now), duck: ambience.duck)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentImage = frame
        personLayer.contents = frame
        let feet = bounds.height * 0.06
        var jump: CGFloat = 0
        var lean = CGFloat(ambience.surfDir) * -0.10
        var stretch: CGFloat = 1
        if let start = specialStart {
            jump = sin(min(1, (now - start) / 0.9) * .pi) * bounds.height * 0.10
        }
        switch motion {
        case .falling: lean = sin(now * 12) * 0.06
        case .landing(let start):
            stretch = 1 - CGFloat(max(0, 1 - (now - start) / Moves.landDuration)) * 0.08
        case .none: break
        }
        personLayer.anchorPoint = CGPoint(x: 0.5, y: 0.06)
        personLayer.position = CGPoint(x: bounds.midX, y: feet)
        var transform = CGAffineTransform(translationX: 0, y: jump)
        transform = transform.rotated(by: lean).scaledBy(x: mirrored ? -1 : 1, y: stretch)
        personLayer.setAffineTransform(transform)
        // A subtle evening halo, plus the same click hearts and landing dust.
        personLayer.shadowColor = NSColor(calibratedRed: 0.88, green: 0.61, blue: 0.35, alpha: 1).cgColor
        personLayer.shadowOpacity = ambience.lights ? 0.7 : 0
        personLayer.shadowRadius = 12
        personLayer.shadowOffset = .zero
        effectsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for heart in hearts {
            let text = CATextLayer()
            text.string = heart.kind == .heart ? "♥" : "·"
            text.fontSize = heart.kind == .heart ? 13 : 10
            text.foregroundColor = NSColor(calibratedRed: 0.64, green: 0.31, blue: 0.21, alpha: 1).cgColor
            text.opacity = Float(max(0, 1 - heart.age / heart.life))
            text.contentsScale = window?.backingScaleFactor ?? 2
            text.frame = CGRect(x: heart.x / 36 * bounds.width, y: (1 - heart.y / 36) * bounds.height, width: 20, height: 20)
            effectsLayer.addSublayer(text)
        }
        CATransaction.commit()
        updateMousePassthrough()
    }

    /// Priority: gravity, a click celebration, the lid, a tilt, then the dance.
    private func fullPose(at t: TimeInterval, _ choreo: Choreographer, _ amb: Ambience) -> Pose {
        switch motion {
        case .falling(let s): return Moves.fall(t: max(0, t - s))
        case .landing(let s): if t - s < Moves.landDuration { return Moves.land(t: max(0, t - s)) }
        case .none: break
        }
        if let s = specialStart, t - s < 0.9 {
            let p = Self.specialPose(t - s)
            return mirrored ? p.mirrored() : p
        }
        if amb.duck > 0 { return Moves.duck(stage: amb.duck) }
        if amb.surfDir != 0 { return Moves.surf(dir: amb.surfDir) }
        let (move, beat) = choreo.current(now: t)
        let p = move.pose(MoveContext(beat: beat))
        return mirrored ? p.mirrored() : p
    }

    /// Crouch, big jump, land. Played when the dancer is clicked.
    private static func specialPose(_ t: Double) -> Pose {
        var p = Pose()
        if t < 0.12 {
            p.dy = 1; p.lArm = .hangBack; p.rArm = .hangBack
        } else if t < 0.55 {
            p.dy = -5; p.airborne = true; p.headDy = -1
            p.lArm = .up; p.rArm = .up
            p.lLeg = Leg(dx: -1); p.rLeg = Leg(dx: -1)
        } else if t < 0.72 {
            p.dy = 1; p.lArm = .pumpLow; p.rArm = .pumpLow
        } else {
            p.lArm = .hip; p.rArm = .hip
        }
        return p
    }

    func celebrate() {
        specialStart = Date().timeIntervalSinceReferenceDate
        let colors: [UInt32] = [0xFF4F8B, 0xFF7AB8, 0xFFFFFF, 0xFF3355, 0xFFB3D1]
        for _ in 0..<6 {
            hearts.append(Heart(x: Double.random(in: 8...23), y: Double.random(in: 4...12),
                                vx: Double.random(in: -4...4), vy: Double.random(in: -14 ... -7),
                                life: Double.random(in: 0.9...1.4), color: colors.randomElement()!))
        }
    }

    /// A puff of dust at her feet.
    func puffDust() {
        for _ in 0..<8 {
            let side: Double = Bool.random() ? 1 : -1
            hearts.append(Heart(x: Double.random(in: 14...21), y: 31,
                                vx: side * Double.random(in: 8...24), vy: Double.random(in: -9 ... -2),
                                life: Double.random(in: 0.3...0.5), color: 0xD6D9EA, kind: .dust))
        }
    }

    /// Transparent margins must not steal clicks from the desktop. A 1px
    /// sample avoids retaining a second full-resolution copy of every frame.
    private func updateMousePassthrough() {
        guard dragOrigin == nil, let window, let image = currentImage else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard bounds.contains(point) else { window.ignoresMouseEvents = true; return }
        let local = Companions.find(characterID).realistic ? personLayer.convert(point, from: layer) : point
        let x = Int(local.x / bounds.width * CGFloat(image.width))
        let y = Int((1 - local.y / bounds.height) * CGFloat(image.height))
        guard x >= 0, x < image.width, y >= 0, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            window.ignoresMouseEvents = true; return
        }
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { bytes in
            if let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                       bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        window.ignoresMouseEvents = rgba[3] < 24
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        onGrab?()
        dragOrigin = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let window else { return }
        let m = NSEvent.mouseLocation
        let d = CGPoint(x: m.x - origin.x, y: m.y - origin.y)
        if !dragged && hypot(d.x, d.y) < 4 { return }
        dragged = true
        window.setFrameOrigin(CGPoint(x: windowOrigin.x + d.x, y: windowOrigin.y + d.y))
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        if dragged, let window {
            onDragEnd?(window.frame.origin)
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}
