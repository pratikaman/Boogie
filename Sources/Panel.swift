import SwiftUI
import AppKit

// MARK: - Warm studio palette

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Studio {
    static let paper = Color(hex: 0xF7F3EC)
    static let surface = Color(hex: 0xEDE7DC)
    static let ink = Color(hex: 0x312C27)
    static let secondary = Color(hex: 0x796F64)
    static let accent = Color(hex: 0xA44F36)
    static let line = Color(hex: 0xDCD4C8)
    static let sage = Color(hex: 0x5D7258)
}

// MARK: - Actions the panel can trigger

protocol PanelActions: AnyObject {
    func setPaused(_ paused: Bool)
    func setHidden(_ hidden: Bool)
    func setBPM(_ bpm: Int)
    func setScale(_ scale: Int)
    func setLook(_ id: String)
    func openCreator(_ id: String?)
    func setCustomMotion(_ motion: CutoutMotion)
    func setFit(_ id: String)
    func setSkin(_ id: String)
    func setDance(_ id: String)
    func setMove(_ id: String)
    func setSquad(_ n: Int)
    func setLineup(_ ids: [String])
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
    @Published var lookId = "sophia"
    @Published var fitId = "raver"
    @Published var skinId = "fair"
    @Published var moveId = "shuffle"
    @Published var danceId = "shuffle"
    @Published var squad = 1
    @Published var customCompany = false
    @Published var lineup = ["sophia"]
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
    /// Full-height, deterministic layout for documentation snapshots.
    var staticRender = false

    weak var actions: PanelActions?
    weak var choreo: Choreographer?
    private var renderer = SpriteRenderer(fit: Wardrobe.fits[0], skin: Wardrobe.skins[1])
    private var canvas = PixelCanvas()
    private var timer: Timer?
    private let playback = CompanionPlayback()

    func refresh(from s: Settings, loginEnabled: Bool) {
        paused = s.paused
        hidden = s.hidden
        bpm = s.bpm
        scale = s.scale
        lookId = s.lookId
        fitId = s.fitId
        skinId = s.skinId
        moveId = s.moveId
        danceId = s.danceId
        lineup = s.dancerIDs
        squad = lineup.count
        customCompany = s.customLineup != nil
        self.loginEnabled = loginEnabled
        renderer.look = Cast.look(s.lookId, fit: Wardrobe.fit(s.fitId), skin: Wardrobe.skin(s.skinId))
        moveName = choreo?.currentMoveName ?? ""
        surf = s.surf
        duck = s.duck
        lightsMode = s.lightsMode
        if let a = actions?.sensorAvailability() { hasAccel = a.accel; hasLid = a.lid; hasLight = a.light }
        calibStep = 0
        calibMessage = ""
        updatePreview()
    }

    /// A populated model for offscreen rendering.
    static func sample() -> PanelModel {
        let m = PanelModel()
        m.bpm = 118; m.moveName = "Easy groove"; m.tilt = 0.12; m.lid = 112; m.lux = 3
        m.hasAccel = true; m.hasLid = true; m.hasLight = true
        m.lights = true; m.surfing = true
        m.preview = Companions.portrait(m.lookId)
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

    func updatePreview() {
        renderer.look = Cast.look(lookId, fit: Wardrobe.fit(fitId), skin: Wardrobe.skin(skinId))
        if choreo == nil {
            preview = Companions.portrait(lookId)
            moveName = CustomDancerStore.shared.find(lookId)?.motionName
                ?? (Companions.find(lookId).realistic ? (Dances.find(danceId)?.name ?? Dances.all[0].name) : Moves.disco.name)
        } else { tick() }
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
        if let custom = CustomDancerStore.shared.find(lookId) {
            preview = CustomDancerStore.shared.frame(lookId, beat: choreo.beat(now: now), duck: ducking)
            moveName = custom.motionName
            return
        }
        if Companions.find(lookId).realistic {
            let sample = choreo.dance(now: now)
            preview = playback.frame(id: lookId, sample: sample, duck: ducking)
            moveName = sample.routine.name
            return
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
    @ObservedObject private var customStore = CustomDancerStore.shared
    @State private var preferences = false

    init(model: PanelModel, showPreferences: Bool = false) {
        self.model = model
        _preferences = State(initialValue: showPreferences)
        _classics = State(initialValue: !Companions.find(model.lookId).usesImage)
        _displayedLookId = State(initialValue: model.lookId)
    }
    @State private var classics = false
    @State private var displayedLookId: String
    private var character: Companion { Companions.find(model.lookId) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("boogie.").font(.system(size: 30, weight: .medium, design: .serif)).tracking(-1.2)
                    Text("A little company for your desktop.")
                        .font(.system(size: 11)).foregroundColor(Studio.secondary)
                }
                Spacer()
                SmallButton(symbol: preferences ? "xmark" : "slider.horizontal.3",
                            label: preferences ? "Back to companion" : "Preferences") {
                    withAnimation(.easeInOut(duration: 0.18)) { preferences.toggle() }
                }
            }
            .padding(22)
            Rectangle().fill(Studio.line).frame(height: 1)
            if preferences {
                if model.staticRender { preferencesContent } else { preferencesPage }
            } else if model.staticRender {
                companionPage
            } else {
                ScrollView { companionPage }
                    .frame(height: min(600, (NSScreen.main?.visibleFrame.height ?? 900) - 250))
            }
            if !preferences {
                transport.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 14)
            }
            Rectangle().fill(Studio.line).frame(height: 1)
            HStack {
                Circle().fill(model.hidden ? Studio.secondary : Studio.sage).frame(width: 5, height: 5)
                Text(model.hidden ? "Taking a little break" : "Make yourself at home")
                    .font(.system(size: 10)).foregroundColor(Studio.secondary)
                Spacer()
                Button("Quit") { model.actions?.quit() }
                    .font(.system(size: 10)).buttonStyle(.plain).foregroundColor(Studio.secondary)
            }
            .padding(.horizontal, 22).padding(.vertical, 13)
        }
        .frame(width: 380)
        .foregroundColor(Studio.ink)
        .background(Studio.paper)
        .preferredColorScheme(.light)
        .onReceive(model.$lookId) { id in
            guard id != displayedLookId else { return }
            displayedLookId = id
            classics = !Companions.find(id).usesImage
        }
    }

    private var companionPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            stage
            companyControls
            HStack {
                sectionLabel(model.customCompany ? "Choose your dancers" : "Choose your company")
                Spacer()
                Button(classics ? "Back to people" : "Pixel classics") {
                    withAnimation(.easeInOut(duration: 0.18)) { classics.toggle() }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Studio.secondary).buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: classics ? 3 : 2), spacing: 8) {
                ForEach(classics ? Companions.classics : Companions.people) { person in
                    characterButton(person)
                }
            }
            if !customStore.dancers.isEmpty {
                sectionLabel("My dancers")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(Companions.customs) { person in characterButton(person) }
                }
            }
            if model.customCompany { lineupControls }
            Button { model.actions?.openCreator(nil) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.rectangle.badge.plus").font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Create a dancer").font(.system(size: 12, weight: .semibold))
                        Text("Your likeness, brought to life.").font(.system(size: 10)).foregroundColor(Studio.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus").font(.system(size: 12))
                }
                .padding(12).foregroundColor(Studio.accent)
                .background(Studio.surface, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(PressStyle())
            if character.custom {
                Button("Edit \(character.name)…") { model.actions?.openCreator(character.id) }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundColor(Studio.accent)
            }
            HStack {
                sectionLabel(character.custom ? "Motion" : "Dance")
                Spacer()
                if model.staticRender {
                    Label(danceLabel, systemImage: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                } else {
                    Menu {
                        if customStore.find(model.lookId)?.generatedDance != nil {
                            Text(customStore.find(model.lookId)?.generatedDance?.isVideo == true ? "Video dance · follows your tempo" : "Photo groove · 8 poses")
                        } else if character.custom {
                            ForEach(CutoutMotion.allCases) { motion in
                                Button(customStore.find(model.lookId)?.avatar == nil ? motion.name : motion.danceName) {
                                    model.actions?.setCustomMotion(motion)
                                }
                            }
                        } else if character.realistic {
                            Picker("Dance", selection: Binding(get: { model.danceId }, set: {
                                model.actions?.setDance($0); model.danceId = $0
                            })) {
                                Text("Shuffle all dances").tag("shuffle")
                                ForEach(Dances.all) { dance in Text(dance.name).tag(dance.id) }
                            }
                        } else {
                            Picker("Dance", selection: Binding(get: { model.moveId }, set: {
                                model.actions?.setMove($0); model.moveId = $0
                            })) {
                                Text("Shuffle").tag("shuffle")
                                ForEach(Moves.all, id: \.id) { move in Text(move.name).tag(move.id) }
                            }
                        }
                    } label: {
                        Label(danceLabel, systemImage: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                    }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Choose a dance")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionLabel("Set the pace")
                    Spacer()
                    Text("\(model.bpm) BPM").font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Studio.secondary)
                }
                HStack(spacing: 5) {
                    ForEach([("Easy", 92), ("Groove", 118), ("Upbeat", 140), ("Party", 172)], id: \.1) { tempo in
                        Choice(title: tempo.0, selected: model.bpm == tempo.1) {
                            model.actions?.setBPM(tempo.1); model.bpm = tempo.1
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Size")
                HStack(spacing: 4) {
                    ForEach([("S", 3), ("M", 5), ("L", 7), ("XL", 9)], id: \.1) { size in
                        Choice(title: size.0, selected: model.scale == size.1) {
                            model.actions?.setScale(size.1); model.scale = size.1
                        }
                    }
                }
            }
        }
        .padding(22)
    }

    private var companyControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionLabel("Company")
                Spacer()
                Text("\(model.squad) \(model.squad == 1 ? "dancer" : "dancers")")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(Studio.secondary)
            }
            HStack(spacing: 5) {
                ForEach(1...3, id: \.self) { n in
                    Choice(title: ["Solo", "Duo", "Trio"][n - 1], selected: !model.customCompany && model.squad == n) {
                        model.actions?.setSquad(n)
                    }
                }
                Choice(title: "Custom", selected: model.customCompany) {
                    model.actions?.setLineup(model.lineup)
                }
            }
            Text(model.customCompany ? "Select dancers below. Add copies with + in your lineup."
                 : "Groups cycle through the cast. Choose Custom to pick everyone.")
                .font(.system(size: 10)).foregroundColor(Studio.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lineupControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Your lineup")
            ForEach(lineupMembers) { person in
                HStack(spacing: 10) {
                    Button {
                        model.actions?.setLook(person.id)
                    } label: {
                        HStack(spacing: 8) {
                            if let image = Companions.portrait(person.id) {
                                Image(decorative: image, scale: 1).resizable()
                                    .interpolation(person.usesImage ? .high : .none)
                                    .scaledToFit().frame(width: 24, height: 32)
                            }
                            Text(person.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Preview \(person.name)")
                    Button {
                        var ids = model.lineup
                        if let i = ids.lastIndex(of: person.id) { ids.remove(at: i) }
                        model.actions?.setLineup(ids)
                    } label: { Image(systemName: "minus").frame(width: 26, height: 28) }
                        .buttonStyle(.plain).disabled(model.lineup.count == 1)
                        .accessibilityLabel("Remove one \(person.name)")
                    Text("\(model.lineup.filter { $0 == person.id }.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced)).frame(minWidth: 20)
                    Button {
                        model.actions?.setLineup(model.lineup + [person.id])
                    } label: { Image(systemName: "plus").frame(width: 26, height: 28) }
                        .buttonStyle(.plain).accessibilityLabel("Add one \(person.name)")
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Studio.surface, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var lineupMembers: [Companion] {
        var seen = Set<String>()
        return model.lineup.filter { seen.insert($0).inserted }.map { Companions.find($0) }
    }

    private var danceLabel: String {
        if let custom = customStore.find(model.lookId) { return custom.motionName }
        let id = character.realistic ? model.danceId : model.moveId
        if id == "shuffle" { return "Shuffle all dances" }
        return character.realistic ? (Dances.find(id)?.name ?? "Easy groove") : (Moves.named(id)?.name ?? "Shuffle")
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                let paused = !model.paused
                model.actions?.setPaused(paused); model.paused = paused
            } label: {
                Label(model.paused ? "Keep dancing" : "Pause dancing", systemImage: model.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .foregroundColor(.white)
                    .background(Studio.accent, in: RoundedRectangle(cornerRadius: 11))
            }.buttonStyle(PressStyle())
            SmallButton(symbol: "dock.rectangle", label: "Return to Dock") { model.actions?.snapToDock() }
            SmallButton(symbol: model.hidden ? "eye" : "eye.slash", label: model.hidden ? "Show companions" : "Hide companions") {
                let hidden = !model.hidden
                model.actions?.setHidden(hidden); model.hidden = hidden
            }
        }
    }

    private var stage: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16).fill(Studio.surface)
            // An understated paper arch and grounded shadow frame the person.
            UnevenArch().fill(Color(hex: 0xE3D9CA)).frame(width: 168, height: 192).offset(x: 32, y: -1)
            Ellipse().fill(Studio.ink.opacity(0.10)).frame(width: 112, height: 10)
                .blur(radius: 6).offset(x: 36, y: -23)
            if let img = model.preview {
                Image(decorative: img, scale: 1)
                    .resizable().interpolation(character.usesImage ? .high : .none)
                    .scaledToFit().frame(width: character.usesImage ? 175 : 140, height: 204)
                    .offset(x: 35, y: -13)
                    .opacity(model.hidden ? 0.35 : 1)
            } else {
                Text("Preview unavailable").font(.system(size: 11)).foregroundColor(Studio.secondary)
                    .frame(height: 180)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(model.hidden || model.paused ? Studio.secondary : Studio.sage).frame(width: 5, height: 5)
                    Text(model.hidden ? "HIDDEN" : model.paused ? "AT EASE" : "ON YOUR DOCK")
                        .font(.system(size: 8, weight: .semibold)).tracking(1.3)
                    Spacer()
                }
                Spacer()
                Text(character.name).font(.system(size: 25, weight: .regular, design: .serif)).tracking(-0.7)
                    .lineLimit(1).frame(maxWidth: 190, alignment: .leading)
                Text(model.paused ? "Taking five" : model.moveName)
                    .font(.system(size: 10)).foregroundColor(Studio.secondary).padding(.top, 4)
                Text("Click to say hello.\nDrag to wander.")
                    .font(.system(size: 9)).foregroundColor(Studio.secondary)
                    .lineSpacing(3).padding(.top, 15)
            }.padding(18)
        }
        .frame(height: 224)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.name), \(model.paused ? "paused" : model.moveName)")
    }

    private func characterButton(_ person: Companion) -> some View {
        let selected = model.customCompany ? model.lineup.contains(person.id) : model.lookId == person.id
        return Button {
            if model.customCompany {
                let ids = selected ? model.lineup.filter { $0 != person.id } : model.lineup + [person.id]
                model.actions?.setLineup(ids)
            } else {
                model.actions?.setLook(person.id)
            }
        } label: {
            HStack(spacing: 6) {
                if let image = Companions.portrait(person.id) {
                    Image(decorative: image, scale: 1).resizable()
                        .interpolation(person.usesImage ? .high : .none)
                        .scaledToFit().frame(width: 37, height: 58)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    if !classics || person.custom {
                        Text(person.detail).font(.system(size: 9)).foregroundColor(Studio.secondary)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundColor(Studio.accent)
                }
            }
            .padding(.horizontal, 9).frame(maxWidth: .infinity).frame(height: 64)
            .background(selected ? Color.white.opacity(0.75) : Studio.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Studio.accent.opacity(0.65) : .clear))
        }
        .buttonStyle(PressStyle())
        .disabled(model.customCompany && selected && Set(model.lineup).count == 1)
        .accessibilityLabel(person.name).accessibilityValue(selected ? "Selected" : "")
    }

    private var preferencesPage: some View {
        ScrollView { preferencesContent }
            .frame(height: min(567, (NSScreen.main?.visibleFrame.height ?? 900) - 180))
    }

    private var preferencesContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Make it yours.").font(.system(size: 27, design: .serif)).tracking(-0.5)
                Text("Little details for your everyday companion.")
                    .font(.system(size: 11)).foregroundColor(Studio.secondary)
            }
            settingRow("Launch at login", detail: "A familiar face when you start your day.", on: model.loginEnabled) {
                model.actions?.setLogin(!model.loginEnabled)
            }
            Divider().overlay(Studio.line)
            sectionLabel("Respond to your Mac")
            settingRow("Follow the tilt", detail: sensorValue(model.tilt, suffix: " g", available: model.hasAccel), on: model.surf, enabled: model.hasAccel) {
                model.surf.toggle(); model.actions?.setSurf(model.surf)
            }
            settingRow("Duck with the lid", detail: sensorValue(model.lid, suffix: "°", available: model.hasLid), on: model.duck, enabled: model.hasLid) {
                model.duck.toggle(); model.actions?.setDuck(model.duck)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Evening glow").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(sensorValue(model.lux, suffix: " lux", available: model.hasLight))
                        .font(.system(size: 10)).foregroundColor(Studio.secondary)
                }
                HStack(spacing: 5) {
                    ForEach([("Auto", "auto"), ("On", "on"), ("Off", "off")], id: \.1) { mode in
                        Choice(title: mode.0, selected: model.lightsMode == mode.1) {
                            model.lightsMode = mode.1; model.actions?.setLightsMode(mode.1)
                        }
                    }
                }
            }
            if model.hasAccel {
                HStack {
                    Button("Reset level") { model.actions?.rezeroTilt(); model.calibMessage = "Level reset." }
                    Spacer()
                    Button(model.calibStep == 0 ? "Calibrate tilt" : "Tilt right, then tap") { model.calibrateTapped() }
                }.font(.system(size: 11)).buttonStyle(.plain).foregroundColor(Studio.accent)
                if !model.calibMessage.isEmpty {
                    Text(model.calibMessage).font(.system(size: 10)).foregroundColor(Studio.secondary)
                }
            }
            if model.lookId == "boogie" { wardrobe }
            Divider().overlay(Studio.line)
            VStack(alignment: .leading, spacing: 9) {
                sectionLabel("The people behind the people")
                Text("Sophia, Manuel, Carla & Nathan · Renderpeople")
                    .font(.system(size: 11)).lineSpacing(5).foregroundColor(Studio.secondary)
                HStack(spacing: 16) {
                    if model.staticRender {
                        Text("Renderpeople ↗")
                    } else {
                        Link("Renderpeople ↗", destination: URL(string: "https://renderpeople.com/free-3d-people/")!)
                    }
                }.font(.system(size: 11)).foregroundColor(Studio.accent)
            }
        }.padding(22)
    }


    private var wardrobe: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Boogie's wardrobe")
            HStack {
                ForEach(Wardrobe.fits, id: \.id) { fit in
                    Button {
                        model.actions?.setFit(fit.id); model.fitId = fit.id
                    } label: {
                        Circle().fill(Color(hex: fit.top)).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(model.fitId == fit.id ? Studio.ink : .clear, lineWidth: 2).padding(-3))
                    }.buttonStyle(PressStyle()).help(fit.name).accessibilityLabel(fit.name)
                }
            }
            HStack {
                ForEach(Wardrobe.skins, id: \.id) { skin in
                    Button {
                        model.actions?.setSkin(skin.id); model.skinId = skin.id
                    } label: {
                        Circle().fill(Color(hex: skin.base)).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(model.skinId == skin.id ? Studio.ink : .clear, lineWidth: 2).padding(-3))
                    }.buttonStyle(PressStyle()).help(skin.name).accessibilityLabel(skin.name)
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(Studio.secondary)
    }

    private func sensorValue(_ value: Double?, suffix: String, available: Bool) -> String {
        guard available else { return "Not available on this Mac" }
        guard let value else { return "Waiting for a reading" }
        return String(format: suffix == " g" ? "%+.2f" : "%.0f", value) + suffix
    }

    private func settingRow(_ title: String, detail: String, on: Bool, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 10)).foregroundColor(Studio.secondary)
                }
                Spacer()
                Capsule().fill(on && enabled ? Studio.sage : Studio.line).frame(width: 30, height: 18)
                    .overlay(Circle().fill(.white).frame(width: 14, height: 14).offset(x: on && enabled ? 6 : -6))
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.6)
            .accessibilityLabel(title).accessibilityValue(enabled ? (on ? "On" : "Off") : "Unavailable")
    }
}

struct UnevenArch: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.width / 2))
            p.addArc(center: CGPoint(x: r.midX, y: r.minY + r.width / 2), radius: r.width / 2,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath()
        }
    }
}

private struct Choice: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? Studio.accent : Studio.secondary)
                .frame(maxWidth: .infinity).frame(height: 29)
                .background(selected ? Color.white : Studio.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Studio.line : .clear))
        }.buttonStyle(PressStyle()).accessibilityValue(selected ? "Selected" : "")
    }
}

private struct SmallButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundColor(Studio.secondary).frame(width: 40, height: 40)
                .background(Studio.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(PressStyle()).help(label).accessibilityLabel(label)
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(InteractionFeedback(pressed: configuration.isPressed))
    }
}

private struct InteractionFeedback: ViewModifier {
    let pressed: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(pressed ? 0.72 : hovering ? 0.86 : 1)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}
