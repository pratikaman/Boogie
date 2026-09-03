import AppKit

/// The transparent, always-on-top panel one dancer lives in.
final class DancerWindow: NSPanel {
    let dancer: DancerView

    init(index: Int, renderer: SpriteRenderer, scale: Int) {
        let size = CGFloat(PixelCanvas.width * scale)
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        dancer = DancerView(index: index, renderer: renderer, frame: rect)
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

/// Renders the sprite into a nearest-neighbour scaled layer and handles
/// click (celebrate), drag (move) and right-click (menu).
final class DancerView: NSView {
    let index: Int
    var renderer: SpriteRenderer

    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?

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

    init(index: Int, renderer: SpriteRenderer, frame: NSRect) {
        self.index = index
        self.renderer = renderer
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        layer?.contentsGravity = .resize
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Animation

    func tick(now: TimeInterval, choreo: Choreographer) {
        if let s = specialStart, now - s >= 0.9 { specialStart = nil }

        var pose = fullPose(at: now, choreo)
        let prev = fullPose(at: now - 0.08, choreo)
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

        canvas.clear()
        renderer.draw(pose, bunLag: bunLag, hearts: hearts, into: &canvas)
        layer?.contents = canvas.cgImage()
    }

    private func fullPose(at t: TimeInterval, _ choreo: Choreographer) -> Pose {
        var p: Pose
        if let s = specialStart, t - s < 0.9 {
            p = Self.specialPose(t - s)
        } else {
            let (move, beat) = choreo.current(now: t)
            p = move.pose(MoveContext(beat: beat))
        }
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

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
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
