import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let settings = Settings.shared
    private var choreo: Choreographer!
    private var windows: [DancerWindow] = []
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        choreo = Choreographer(bpm: settings.bpm, lockedMoveId: settings.moveId == "shuffle" ? nil : settings.moveId)
        choreo.paused = settings.paused

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "figure.dance", accessibilityDescription: "Boogie")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Boogie"
        }
        menu.delegate = self
        statusItem.menu = menu

        rebuildDancers()

        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: Dancers

    private func rebuildDancers() {
        windows.forEach { $0.orderOut(nil) }
        windows = (0..<settings.squad).map { i in
            let w = DancerWindow(index: i, renderer: renderer(for: i), scale: settings.scale)
            w.dancer.onClick = { [weak w] in w?.dancer.celebrate() }
            w.dancer.onRightClick = { [weak self] _ in
                guard let self else { return }
                self.menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
            w.dancer.onDragEnd = { [weak self] origin in self?.settings.setPosition(i, origin) }
            return w
        }
        layout()
        if !settings.hidden { windows.forEach { $0.orderFrontRegardless() } }
    }

    /// Each dancer in a squad gets its own fit and skin, cycling from the chosen ones.
    private func renderer(for i: Int) -> SpriteRenderer {
        let fits = Wardrobe.fits, skins = Wardrobe.skins
        let f = fits.firstIndex { $0.id == settings.fitId } ?? 0
        let s = skins.firstIndex { $0.id == settings.skinId } ?? 1
        return SpriteRenderer(fit: fits[(f + i) % fits.count], skin: skins[(s + 2 * i) % skins.count])
    }

    private func applyWardrobe() {
        for (i, w) in windows.enumerated() {
            let r = renderer(for: i)
            w.dancer.renderer.fit = r.fit
            w.dancer.renderer.skin = r.skin
        }
    }

    /// Docked dancers stand on the Dock (or the bottom screen edge), centred.
    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let scale = settings.scale
        let size = CGFloat(PixelCanvas.width * scale)
        let vf = screen.visibleFrame
        let gap: CGFloat = 6
        let n = windows.count
        for (i, w) in windows.enumerated() {
            let origin: CGPoint
            if let saved = settings.position(i) {
                origin = saved
            } else {
                let offset = CGFloat(i) - CGFloat(n - 1) / 2
                // Feet are 4 sprite rows above the bottom of the canvas.
                origin = CGPoint(x: (vf.midX + offset * (size + gap) - size / 2).rounded(),
                                 y: vf.minY - CGFloat(4 * scale))
            }
            w.setFrame(NSRect(origin: origin, size: CGSize(width: size, height: size)), display: true)
        }
    }

    private func tick() {
        guard !settings.hidden else { return }
        let now = Date().timeIntervalSinceReferenceDate
        for w in windows { w.dancer.tick(now: now, choreo: choreo) }
    }

    @objc private func screensChanged() { layout() }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: "Now: \(choreo.currentMoveName) · \(settings.bpm) BPM", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(item(settings.paused ? "Dance!" : "Take five", #selector(togglePause)))
        menu.addItem(.separator())

        menu.addItem(submenu("Move", selected: settings.moveId, #selector(pickMove),
                             [("Shuffle", "shuffle")] + Moves.all.map { ($0.name, $0.id) }))
        menu.addItem(submenu("Tempo", selected: settings.bpm, #selector(pickTempo),
                             [("Chill · 92", 92), ("Groove · 118", 118), ("Hype · 140", 140), ("Rave · 172", 172)]))
        menu.addItem(submenu("Size", selected: settings.scale, #selector(pickSize),
                             [("Small", 3), ("Medium", 5), ("Large", 7), ("Huge", 9)]))
        menu.addItem(submenu("Fit", selected: settings.fitId, #selector(pickFit), Wardrobe.fits.map { ($0.name, $0.id) }))
        menu.addItem(submenu("Skin", selected: settings.skinId, #selector(pickSkin), Wardrobe.skins.map { ($0.name, $0.id) }))
        menu.addItem(submenu("Squad", selected: settings.squad, #selector(pickSquad),
                             [("Solo", 1), ("Duo", 2), ("Trio", 3)]))
        menu.addItem(.separator())

        menu.addItem(item("Snap to Dock", #selector(snapToDock)))
        menu.addItem(item(settings.hidden ? "Show" : "Hide", #selector(toggleHidden)))
        let login = item("Launch at login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Click her for hearts. Drag her anywhere.", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(item("Quit Boogie", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func submenu<T: Equatable>(_ title: String, selected: T, _ action: Selector, _ options: [(String, T)]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        for (name, value) in options {
            let i = item(name, action)
            i.representedObject = value
            i.state = value == selected ? .on : .off
            sub.addItem(i)
        }
        parent.submenu = sub
        return parent
    }

    // MARK: Actions

    @objc private func togglePause() {
        settings.paused.toggle()
        choreo.paused = settings.paused
    }

    @objc private func pickMove(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.moveId = id
        choreo.lockedMoveId = id == "shuffle" ? nil : id
    }

    @objc private func pickTempo(_ sender: NSMenuItem) {
        guard let bpm = sender.representedObject as? Int else { return }
        settings.bpm = bpm
        choreo.setBPM(bpm)
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? Int else { return }
        settings.scale = scale
        rebuildDancers()
    }

    @objc private func pickFit(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.fitId = id
        applyWardrobe()
    }

    @objc private func pickSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.skinId = id
        applyWardrobe()
    }

    @objc private func pickSquad(_ sender: NSMenuItem) {
        guard let n = sender.representedObject as? Int else { return }
        settings.squad = n
        settings.clearPositions()
        rebuildDancers()
    }

    @objc private func snapToDock() {
        settings.clearPositions()
        layout()
    }

    @objc private func toggleHidden() {
        settings.hidden.toggle()
        if settings.hidden {
            windows.forEach { $0.orderOut(nil) }
        } else {
            windows.forEach { $0.orderFrontRegardless() }
        }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
