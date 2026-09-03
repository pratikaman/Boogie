import SwiftUI
import AppKit

// MARK: - Theme ("Club Boogie": black-light purple, neon pink, a touch of cyan)

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Club {
    static let bg = Color(hex: 0x0A0710)
    static let card = Color(hex: 0x160F20)
    static let stroke = Color.white.opacity(0.07)
    static let pink = Color(hex: 0xFF2E9A)
    static let cyan = Color(hex: 0x00E5FF)
    static let amber = Color(hex: 0xFFB020)
    static let red = Color(hex: 0xFF3B3B)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.35)
}

extension View {
    /// Neon-tube glow.
    func neon(_ c: Color, strength: Double = 1) -> some View {
        self.shadow(color: c.opacity(0.9 * strength), radius: 5)
            .shadow(color: c.opacity(0.45 * strength), radius: 14)
    }
}

// MARK: - Actions the panel can trigger

protocol PanelActions: AnyObject {
    func setPaused(_ paused: Bool)
    func setHidden(_ hidden: Bool)
    func setBPM(_ bpm: Int)
    func setScale(_ scale: Int)
    func setFit(_ id: String)
    func setSkin(_ id: String)
    func setMove(_ id: String)
    func setSquad(_ n: Int)
    func setLogin(_ enabled: Bool)
    func snapToDock()
    func quit()
    func setSurf(_ on: Bool)
    func setDuck(_ on: Bool)
    func setLightsMode(_ mode: String)
    func rezeroTilt()
    func calibrateTilt() -> Bool
    func sensorReadout() -> SensorReadout
    func ambienceNow() -> Ambience
    func sensorAvailability() -> (accel: Bool, lid: Bool, light: Bool)
}

// MARK: - Model

final class PanelModel: ObservableObject {
    @Published var paused = false
    @Published var hidden = false
    @Published var bpm = 118
    @Published var scale = 5
    @Published var fitId = "raver"
    @Published var skinId = "fair"
    @Published var moveId = "shuffle"
    @Published var squad = 1
    @Published var loginEnabled = false
    @Published var moveName = ""
    @Published var preview: CGImage?

    // Sensors
    @Published var tilt: Double?
    @Published var lid: Double?
    @Published var lux: Double?
    @Published var surf = true
    @Published var duck = true
    @Published var lightsMode = "auto"
    @Published var lights = false
    @Published var surfing = false
    @Published var ducking = 0
    @Published var hasAccel = false
    @Published var hasLid = false
    @Published var hasLight = false
    @Published var calibStep = 0
    @Published var calibMessage = ""
    /// Offscreen render: AppKit-backed controls can't be drawn, so fake them.
    var staticRender = false

    weak var actions: PanelActions?
    weak var choreo: Choreographer?
    private var renderer = SpriteRenderer(fit: Wardrobe.fits[0], skin: Wardrobe.skins[1])
    private var canvas = PixelCanvas()
    private var timer: Timer?

    func refresh(from s: Settings, loginEnabled: Bool) {
        paused = s.paused
        hidden = s.hidden
        bpm = s.bpm
        scale = s.scale
        fitId = s.fitId
        skinId = s.skinId
        moveId = s.moveId
        squad = s.squad
        self.loginEnabled = loginEnabled
        renderer.fit = Wardrobe.fit(s.fitId)
        renderer.skin = Wardrobe.skin(s.skinId)
        moveName = choreo?.currentMoveName ?? ""
        surf = s.surf
        duck = s.duck
        lightsMode = s.lightsMode
        if let a = actions?.sensorAvailability() { hasAccel = a.accel; hasLid = a.lid; hasLight = a.light }
        calibStep = 0
        calibMessage = ""
    }

    /// A populated model for offscreen rendering.
    static func sample() -> PanelModel {
        let m = PanelModel()
        m.bpm = 118; m.moveName = "Disco"; m.tilt = 0.12; m.lid = 112; m.lux = 3
        m.hasAccel = true; m.hasLid = true; m.hasLight = true
        m.lights = true; m.surfing = true
        var canvas = PixelCanvas()
        m.renderer.draw(Moves.disco.pose(MoveContext(beat: 0.1)), bunLag: 0, hearts: [], into: &canvas,
                        fx: StageFX(lights: true, beat: 0.1))
        m.preview = canvas.cgImage()
        m.staticRender = true
        return m
    }

    func calibrateTapped() {
        if calibStep == 0 {
            actions?.rezeroTilt()
            calibStep = 1
            calibMessage = "Flat for a second, then tilt the RIGHT edge down and tap again."
        } else if actions?.calibrateTilt() == true {
            calibStep = 0
            calibMessage = "Calibrated. Tilt away."
        } else {
            calibMessage = "Not enough tilt yet. Right edge down, then tap again."
        }
    }

    func startPreview() {
        stopPreview()
        let t = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stopPreview() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let choreo else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let (move, beat) = choreo.current(now: now)
        var pose = move.pose(MoveContext(beat: beat))
        let (pm, pb) = choreo.current(now: now - 0.08)
        let prev = pm.pose(MoveContext(beat: pb))
        pose.eyesClosed = Int(now * 10) % 40 == 0
        if let r = actions?.sensorReadout() { tilt = r.tilt; lid = r.lid; lux = r.lux }
        if let a = actions?.ambienceNow() {
            lights = a.lights
            surfing = a.surfDir != 0
            ducking = a.duck
            if a.duck > 0 { pose = Moves.duck(stage: a.duck) } else if a.surfDir != 0 { pose = Moves.surf(dir: a.surfDir) }
        }
        canvas.clear()
        renderer.draw(pose, bunLag: (prev.dy + prev.headDy) - (pose.dy + pose.headDy), hearts: [], into: &canvas,
                      fx: StageFX(lights: lights, beat: beat))
        preview = canvas.cgImage()
        moveName = choreo.currentMoveName
    }
}

// MARK: - Panel

struct PanelView: View {
    @ObservedObject var model: PanelModel

    private let tempos: [(String, Int)] = [("Chill", 92), ("Groove", 118), ("Hype", 140), ("Rave", 172)]
    private let sizes: [(String, Int)] = [("S", 3), ("M", 5), ("L", 7), ("XL", 9)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Marquee()
            stage
            transport

            section("MOVE") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    Chip(title: "Shuffle", selected: model.moveId == "shuffle", color: Club.cyan) { pick(move: "shuffle") }
                    ForEach(Moves.all, id: \.id) { m in
                        Chip(title: m.name, selected: model.moveId == m.id, color: Club.pink) { pick(move: m.id) }
                    }
                }
            }

            section("TEMPO") {
                HStack(spacing: 6) {
                    ForEach(tempos, id: \.1) { t in
                        Chip(title: t.0, detail: "\(t.1)", selected: model.bpm == t.1, color: Club.cyan) {
                            model.actions?.setBPM(t.1); model.bpm = t.1
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                section("SIZE") {
                    HStack(spacing: 6) {
                        ForEach(sizes, id: \.1) { s in
                            Chip(title: s.0, selected: model.scale == s.1, color: Club.pink) {
                                model.actions?.setScale(s.1); model.scale = s.1
                            }
                        }
                    }
                }
                section("SQUAD") {
                    HStack(spacing: 6) {
                        ForEach(1...3, id: \.self) { n in
                            Chip(title: String(repeating: "♀", count: n), selected: model.squad == n, color: Club.pink) {
                                model.actions?.setSquad(n); model.squad = n
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                section("FIT", fill: false) {
                    HStack(spacing: 5) {
                        ForEach(Wardrobe.fits, id: \.id) { f in
                            Swatch(top: Color(hex: f.hair), bottom: Color(hex: f.top), selected: model.fitId == f.id) {
                                model.actions?.setFit(f.id); model.fitId = f.id
                            }.help(f.name)
                        }
                    }
                }
                section("SKIN", fill: false) {
                    HStack(spacing: 5) {
                        ForEach(Wardrobe.skins, id: \.id) { s in
                            Swatch(top: Color(hex: s.base), bottom: Color(hex: s.base), selected: model.skinId == s.id) {
                                model.actions?.setSkin(s.id); model.skinId = s.id
                            }.help(s.name)
                        }
                    }
                }
            }

            sensorsSection
            footer
        }
        .padding(14)
        .frame(width: 320)
        .background(Club.bg)
        .preferredColorScheme(.dark)
    }

    private func pick(move id: String) {
        model.actions?.setMove(id)
        model.moveId = id
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("BOOGIE")
                .font(.system(size: 24, weight: .black, design: .rounded)).italic()
                .foregroundColor(Club.pink)
                .neon(Club.pink)
            Text("since 1998")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1)
                .foregroundColor(Club.cyan)
                .neon(Club.cyan, strength: 0.6)
            Spacer()
            LiveBadge(state: model.hidden ? .hidden : (model.paused ? .paused : .live))
        }
    }

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Club.card)
            SynthGrid().padding(.top, 70)
            RadialGradient(colors: [Club.pink.opacity(0.32), .clear], center: .init(x: 0.5, y: 0.05), startRadius: 0, endRadius: 170)
            if let img = model.preview {
                Image(decorative: img, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 144, height: 144)
                    .offset(y: -18)
            }
            VStack {
                Spacer()
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NOW DANCING")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(2)
                            .foregroundColor(Club.faint)
                        Text(model.moveName)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text("\(model.bpm)")
                            .font(.system(size: 28, weight: .black, design: .rounded)).monospacedDigit()
                            .foregroundColor(Club.cyan)
                            .neon(Club.cyan)
                        Text("BPM")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(Club.faint)
                    }
                }
                .padding(12)
                .background(LinearGradient(colors: [.clear, Club.bg.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(height: 196)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Club.stroke))
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                model.actions?.setPaused(!model.paused)
                model.paused.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.paused ? "play.fill" : "pause.fill")
                    Text(model.paused ? "Dance!" : "Take five")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Club.pink.opacity(0.10)))
                .overlay(Capsule().stroke(Club.pink, lineWidth: 1.5))
                .foregroundColor(Club.pink)
                .shadow(color: Club.pink.opacity(0.35), radius: 10)
            }
            .buttonStyle(.plain)

            IconButton(symbol: "dock.rectangle", help: "Snap to Dock") { model.actions?.snapToDock() }
            IconButton(symbol: model.hidden ? "eye" : "eye.slash", help: model.hidden ? "Show" : "Hide") {
                model.actions?.setHidden(!model.hidden)
                model.hidden.toggle()
            }
        }
    }

    private var sensorsSection: some View {
        section("SENSORS") {
            HStack(spacing: 6) {
                SensorCard(title: "TILT",
                           value: model.hasAccel ? (model.tilt.map { String(format: "%+.2f g", $0) } ?? "zeroing") : "none",
                           state: !model.hasAccel ? "no sensor" : (!model.surf ? "surf off" : (model.surfing ? "surfing!" : "surf on")),
                           active: model.surfing, enabled: model.hasAccel) {
                    model.surf.toggle(); model.actions?.setSurf(model.surf)
                }
                SensorCard(title: "LID",
                           value: model.hasLid ? (model.lid.map { "\(Int($0))°" } ?? "…") : "none",
                           state: !model.hasLid ? "no sensor" : (!model.duck ? "duck off" : (model.ducking > 0 ? "ducking!" : "duck on")),
                           active: model.ducking > 0, enabled: model.hasLid) {
                    model.duck.toggle(); model.actions?.setDuck(model.duck)
                }
                SensorCard(title: "LUX",
                           value: model.hasLight ? (model.lux.map { "\(Int($0))" } ?? "…") : "none",
                           state: !model.hasLight && model.lightsMode == "auto" ? "no sensor"
                                : (model.lightsMode == "auto" ? (model.lights ? "dark · lit" : "auto") : (model.lightsMode == "on" ? "always on" : "off")),
                           active: model.lights, enabled: true) {
                    let next = ["auto": "on", "on": "off", "off": "auto"][model.lightsMode] ?? "auto"
                    model.lightsMode = next; model.actions?.setLightsMode(next)
                }
            }
            HStack(spacing: 6) {
                Chip(title: "Re-zero tilt", selected: false, color: Club.cyan) {
                    model.actions?.rezeroTilt(); model.calibMessage = "Level reset."
                }
                Chip(title: model.calibStep == 0 ? "Calibrate tilt" : "Tilt right & tap", selected: model.calibStep != 0, color: Club.cyan) {
                    model.calibrateTapped()
                }
            }
            Text(model.calibMessage.isEmpty ? "tilt = she surfs · lid down = she ducks · dark = lights on" : model.calibMessage)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Club.faint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.staticRender {
                Text("Launch at login")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Club.dim)
                Capsule().fill(Color.white.opacity(0.12)).frame(width: 26, height: 15)
                    .overlay(Circle().fill(Color.white.opacity(0.9)).frame(width: 11, height: 11).offset(x: -5))
            } else {
                Toggle(isOn: Binding(get: { model.loginEnabled },
                                     set: { model.actions?.setLogin($0); model.loginEnabled = $0 })) {
                    Text("Launch at login")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Club.dim)
                        .fixedSize()
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Club.pink)
            }
            Spacer()
            Text("tap = hearts · drag = move")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Club.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button { model.actions?.quit() } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Club.faint)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Quit Boogie")
        }
        .padding(.top, 2)
    }

    private func section<Content: View>(_ title: String, fill: Bool = true, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(2)
                .foregroundColor(Club.faint)
            content()
        }
        .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
    }
}

// MARK: - Components

/// Chasing cabaret bulbs.
private struct Marquee: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.14)) { ctx in
            let phase = Int(ctx.date.timeIntervalSinceReferenceDate / 0.14) % 3
            HStack(spacing: 0) {
                ForEach(0..<26, id: \.self) { i in
                    let on = (i + phase) % 3 == 0
                    Circle()
                        .fill(on ? Club.pink : Club.pink.opacity(0.16))
                        .frame(width: 5, height: 5)
                        .shadow(color: on ? Club.pink.opacity(0.9) : .clear, radius: 4)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 8)
    }
}

private struct LiveBadge: View {
    enum State { case live, paused, hidden }
    let state: State

    var body: some View {
        let (label, color) = { () -> (String, Color) in
            switch state {
            case .live: return ("LIVE", Club.red)
            case .paused: return ("PAUSED", Club.amber)
            case .hidden: return ("HIDDEN", Club.faint)
            }
        }()
        TimelineView(.periodic(from: .now, by: 0.6)) { ctx in
            let blinkOn = state != .live || Int(ctx.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
            HStack(spacing: 5) {
                Circle()
                    .fill(color.opacity(blinkOn ? 1 : 0.25))
                    .frame(width: 6, height: 6)
                    .shadow(color: blinkOn ? color.opacity(0.9) : .clear, radius: 4)
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(2)
                    .foregroundColor(color)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        }
    }
}

private struct Chip: View {
    let title: String
    var detail: String? = nil
    let selected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .opacity(0.7)
                }
            }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(selected ? color.opacity(0.16) : Color.white.opacity(0.05)))
                .overlay(Capsule().stroke(selected ? color.opacity(0.85) : Club.stroke, lineWidth: 1))
                .foregroundColor(selected ? color : Club.dim)
                .shadow(color: selected ? color.opacity(0.45) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct Swatch: View {
    let top: Color
    let bottom: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(bottom)
                Circle().trim(from: 0, to: 0.5).fill(top).rotationEffect(.degrees(180))
            }
            .frame(width: 21, height: 21)
            .overlay(Circle().stroke(selected ? Club.pink : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
            .shadow(color: selected ? Club.pink.opacity(0.7) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}

/// Live sensor readout; tapping toggles that crossover.
private struct SensorCard: View {
    let title: String
    let value: String
    let state: String
    let active: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(2)
                    .foregroundColor(Club.faint)
                Text(value)
                    .font(.system(size: 14, weight: .black, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(!enabled ? Club.faint : (active ? Club.pink : .white))
                Text(state)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(active ? Club.pink : Club.dim)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Club.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Club.pink.opacity(0.8) : Club.stroke))
            .shadow(color: active ? Club.pink.opacity(0.35) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Club.dim)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().stroke(Club.stroke))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Synthwave floor: perspective grid fading in from the horizon.
private struct SynthGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let horizon: CGFloat = 0
            let vanish = CGPoint(x: size.width / 2, y: horizon - 40)
            var lines = Path()
            for k in 1...7 {
                let f = pow(CGFloat(k) / 7, 1.8)
                let y = horizon + (size.height - horizon) * f
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            for k in -6...6 {
                let x = size.width / 2 + CGFloat(k) * size.width / 7
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: vanish)
            }
            ctx.stroke(lines, with: .color(Club.pink.opacity(0.28)), lineWidth: 1)
            var top = Path()
            top.move(to: CGPoint(x: 0, y: horizon + 0.5))
            top.addLine(to: CGPoint(x: size.width, y: horizon + 0.5))
            ctx.stroke(top, with: .color(Club.cyan.opacity(0.35)), lineWidth: 1)
        }
        .mask(LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .init(x: 0.5, y: 0.6)))
    }
}
