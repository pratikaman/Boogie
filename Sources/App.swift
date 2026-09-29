import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, PanelActions {
    private var statusItem: NSStatusItem!
    private let settings: Settings
    private var choreo: Choreographer!
    private var windows: [DancerWindow] = []
    private var timer: Timer?
    private let model = PanelModel()
    private let popover = NSPopover()
    private let sensors = Sensors()
    private let crossover = Crossover()
    private var lastReadout = SensorReadout()
    private var lastAmbience = Ambience()
    private var wasSurfing = false
    private var lastTick: TimeInterval = 0

    // Gravity: dancers currently falling, by index.
    private struct Fall { var vy: CGFloat = 0; var bounced = false }
    private var falls: [Int: Fall] = [:]
    private static let gravity: CGFloat = 2600   // points/s²
    private static let debugSensors = ProcessInfo.processInfo.environment["BOOGIE_DEBUG_SENSORS"] != nil

    init(settings: Settings = .shared) {
        self.settings = settings
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        choreo = Choreographer(bpm: settings.bpm, lockedMoveId: settings.moveId == "shuffle" ? nil : settings.moveId)
        choreo.paused = settings.paused
        crossover.surfEnabled = settings.surf
        crossover.duckEnabled = settings.duck
        crossover.lightsMode = settings.lightsMode
        sensors.axis = settings.tiltAxis
        sensors.sign = settings.tiltSign

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "figure.dance", accessibilityDescription: "Boogie")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Boogie"
            button.target = self
            button.action = #selector(togglePanel)
        }

        model.actions = self
        model.choreo = choreo
        let hosting = NSHostingController(rootView: PanelView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.delegate = self

        rebuildDancers()

        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: Panel

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            showPanel(relativeTo: button, edge: .minY)
        }
    }

    private func showPanel(relativeTo view: NSView, edge: NSRectEdge) {
        model.refresh(from: settings, loginEnabled: SMAppService.mainApp.status == .enabled)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
    }

    func popoverWillShow(_ notification: Notification) { model.startPreview() }
    func popoverDidClose(_ notification: Notification) { model.stopPreview() }

    // MARK: Dancers

    private func rebuildDancers() {
        windows.forEach { $0.orderOut(nil) }
        windows = (0..<settings.squad).map { i in
            let w = DancerWindow(index: i, characterID: characterID(for: i), renderer: renderer(for: i), scale: settings.scale)
            w.dancer.onClick = { [weak w] in w?.dancer.celebrate() }
            w.dancer.onRightClick = { [weak self, weak w] _ in
                guard let self, let w else { return }
                if self.popover.isShown { self.popover.performClose(nil) }
                self.showPanel(relativeTo: w.dancer, edge: .maxY)
            }
            w.dancer.onDragEnd = { [weak self] _ in self?.release(i) }
            w.dancer.onGrab = { [weak self, weak w] in
                self?.falls[i] = nil
                w?.dancer.motion = .none
            }
            return w
        }
        layout()
        if !settings.hidden { windows.forEach { $0.orderFrontRegardless() } }
    }

    private func characterID(for index: Int) -> String {
        let roster = Companions.roster(for: settings.lookId)
        let first = roster.firstIndex { $0.id == settings.lookId } ?? 0
        return roster[(first + index) % roster.count].id
    }

    /// A squad cycles through the cast from the chosen dancer; Boogie's fit and skin cycle too.
    private func renderer(for i: Int) -> SpriteRenderer {
        let fits = Wardrobe.fits, skins = Wardrobe.skins, cast = Cast.roster
        let f = fits.firstIndex { $0.id == settings.fitId } ?? 0
        let s = skins.firstIndex { $0.id == settings.skinId } ?? 1
        let c = cast.firstIndex { $0.id == settings.lookId } ?? 0
        return SpriteRenderer(look: Cast.look(cast[(c + i) % cast.count].id,
                                              fit: fits[(f + i) % fits.count], skin: skins[(s + 2 * i) % skins.count]))
    }

    private func applyWardrobe() {
        for (i, w) in windows.enumerated() { w.dancer.renderer.look = renderer(for: i).look }
        model.refresh(from: settings, loginEnabled: model.loginEnabled)
    }

    /// Docked dancers stand on the Dock (or the bottom screen edge), centred.
    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let scale = settings.scale
        let size = Companions.size(for: settings.lookId, scale: scale)
        let vf = screen.visibleFrame
        let gap: CGFloat = 6
        let n = windows.count
        for (i, w) in windows.enumerated() {
            let origin: CGPoint
            if let saved = settings.position(i) {
                origin = saved
            } else {
                let offset = CGFloat(i) - CGFloat(n - 1) / 2
                // Each renderer reserves a transparent margin below the feet.
                origin = CGPoint(x: (vf.midX + offset * (size.width + gap) - size.width / 2).rounded(),
                                 y: vf.minY - Companions.footInset(for: w.dancer.characterID, scale: scale))
            }
            w.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        // Anyone left hanging in the air (a saved spot above the Dock) drops.
        for i in windows.indices { release(i) }
    }

    // MARK: Gravity

    /// The window origin y at which her feet touch the Dock (or the screen bottom).
    private func floorY(for w: DancerWindow) -> CGFloat {
        let screen = w.screen ?? NSScreen.screens.first
        return (screen?.visibleFrame.minY ?? 0) - Companions.footInset(for: w.dancer.characterID, scale: settings.scale)
    }

    /// Let go of dancer `i`: fall if she's above the floor, otherwise settle and remember the spot.
    private func release(_ i: Int) {
        guard i < windows.count else { return }
        let w = windows[i]
        let floor = floorY(for: w)
        if w.frame.origin.y > floor + 1 {
            falls[i] = Fall()
            w.dancer.motion = .falling(since: Date().timeIntervalSinceReferenceDate)
        } else {
            if w.frame.origin.y < floor { w.setFrameOrigin(CGPoint(x: w.frame.origin.x, y: floor)) }
            falls[i] = nil
            settings.setPosition(i, w.frame.origin)
        }
    }

    private func advanceFalls(now: TimeInterval, dt: CGFloat) {
        for (i, fall) in falls {
            guard i < windows.count else { falls[i] = nil; continue }
            var f = fall
            let w = windows[i]
            let floor = floorY(for: w)
            f.vy -= Self.gravity * dt
            var origin = w.frame.origin
            origin.y += f.vy * dt
            if origin.y > floor {
                w.setFrameOrigin(origin)
                falls[i] = f
                continue
            }
            origin.y = floor
            w.setFrameOrigin(origin)
            let impact = -f.vy
            w.dancer.puffDust()
            if impact > 1000 && !f.bounced {
                // A long drop: one hop back up before she settles.
                f.bounced = true
                f.vy = impact * 0.22
                falls[i] = f
            } else {
                falls[i] = nil
                w.dancer.motion = .landing(since: now)
                settings.setPosition(i, origin)
            }
        }
    }

    private func tick() {
        let now = Date().timeIntervalSinceReferenceDate
        lastReadout = sensors.read(now: now)
        let amb = crossover.update(now: now, readout: lastReadout)
        lastAmbience = amb
        if Self.debugSensors, Int(now * 30) % 30 == 0 {
            let r = lastReadout
            FileHandle.standardError.write("sensors tilt=\(r.tilt.map { String(format: "%+.3f", $0) } ?? "nil") raw=\(sensors.rawDescription) lid=\(r.lid.map { String(Int($0)) } ?? "nil") lux=\(r.lux.map { String(Int($0)) } ?? "nil") surf=\(amb.surfDir) dx=\(String(format: "%.1f", amb.slideDx)) duck=\(amb.duck) lights=\(amb.lights)\n".data(using: .utf8)!)
        }
        let dt = CGFloat(lastTick == 0 ? 1.0 / 30 : min(0.1, now - lastTick))
        lastTick = now
        guard !settings.hidden else { return }
        if amb.slideDx != 0 { slide(by: amb.slideDx) }
        if !falls.isEmpty { advanceFalls(now: now, dt: dt) }
        if wasSurfing && !crossover.surfing {
            // She stopped somewhere new; remember it so she stays there.
            for (i, w) in windows.enumerated() { settings.setPosition(i, w.frame.origin) }
        }
        wasSurfing = crossover.surfing
        for w in windows {
            if amb.celebrate { w.dancer.celebrate() }
            w.dancer.tick(now: now, choreo: choreo, ambience: amb)
        }
    }

    /// Move every dancer sideways, bouncing off the screen edges.
    private func slide(by dx: CGFloat) {
        var hitEdge = false
        for (i, w) in windows.enumerated() where falls[i] == nil {
            guard let screen = w.screen ?? NSScreen.screens.first else { continue }
            let vf = screen.visibleFrame
            var origin = w.frame.origin
            origin.x += dx
            let minX = vf.minX, maxX = vf.maxX - w.frame.width
            if origin.x < minX { origin.x = minX; hitEdge = true }
            if origin.x > maxX { origin.x = maxX; hitEdge = true }
            w.setFrameOrigin(origin)
        }
        if hitEdge { crossover.bounce() }
    }

    @objc private func screensChanged() { layout() }

    // MARK: PanelActions

    func setPaused(_ paused: Bool) {
        settings.paused = paused
        choreo.paused = paused
    }

    func setHidden(_ hidden: Bool) {
        settings.hidden = hidden
        if hidden {
            windows.forEach { $0.orderOut(nil) }
        } else {
            windows.forEach { $0.orderFrontRegardless() }
        }
    }

    func setBPM(_ bpm: Int) {
        settings.bpm = bpm
        choreo.setBPM(bpm)
    }

    func setScale(_ scale: Int) {
        settings.scale = scale
        rebuildDancers()
    }

    func setLook(_ id: String) {
        settings.lookId = id
        rebuildDancers()
        model.refresh(from: settings, loginEnabled: model.loginEnabled)
    }

    func setFit(_ id: String) {
        settings.fitId = id
        applyWardrobe()
    }

    func setSkin(_ id: String) {
        settings.skinId = id
        applyWardrobe()
    }

    func setMove(_ id: String) {
        settings.moveId = id
        choreo.lockedMoveId = id == "shuffle" ? nil : id
    }

    func setSquad(_ n: Int) {
        settings.squad = n
        settings.clearPositions()
        rebuildDancers()
    }

    func setLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        model.loginEnabled = service.status == .enabled
    }

    func snapToDock() {
        settings.clearPositions()
        falls.removeAll()
        windows.forEach { $0.dancer.motion = .none }
        layout()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Sensor crossovers

    func setSurf(_ on: Bool) {
        settings.surf = on
        crossover.surfEnabled = on
    }

    func setDuck(_ on: Bool) {
        settings.duck = on
        crossover.duckEnabled = on
    }

    func setLightsMode(_ mode: String) {
        settings.lightsMode = mode
        crossover.lightsMode = mode
    }

    func rezeroTilt() {
        sensors.rezero()
    }

    /// Call while the right edge of the MacBook is tilted down: picks the
    /// accelerometer axis and sign that mean "slide right".
    func calibrateTilt() -> Bool {
        guard let d = sensors.delta() else { return false }
        let candidates = [(0, d.x), (1, d.y)]
        guard let best = candidates.max(by: { abs($0.1) < abs($1.1) }), abs(best.1) > 0.08 else { return false }
        sensors.axis = best.0
        sensors.sign = best.1 > 0 ? 1 : -1
        settings.tiltAxis = sensors.axis
        settings.tiltSign = sensors.sign
        return true
    }

    func sensorReadout() -> SensorReadout { lastReadout }
    func ambienceNow() -> Ambience { lastAmbience }
    func sensorAvailability() -> (accel: Bool, lid: Bool, light: Bool) {
        (sensors.hasAccel, sensors.hasLid, sensors.hasLight)
    }
}
