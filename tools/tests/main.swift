import AppKit
import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    checks += 1
}
func digest(_ image: CGImage) -> Data {
    let width = 24, height = 32
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { b in
        let ctx = CGContext(data: b.baseAddress, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return Data(bytes)
}

func hasClearEdges(_ image: CGImage) -> Bool {
    let w = image.width, h = image.height
    var alpha = [UInt8](repeating: 0, count: w * h * 4)
    alpha.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (0..<w).allSatisfy { alpha[$0 * 4 + 3] < 24 && alpha[((h - 1) * w + $0) * 4 + 3] < 24 }
        && (0..<h).allSatisfy { alpha[$0 * w * 4 + 3] < 24 && alpha[($0 * w + w - 1) * 4 + 3] < 24 }
}

let frames = CharacterFrames(root: URL(fileURLWithPath: CommandLine.arguments[1]))
for person in Companions.people {
    guard let manifest = frames.manifest(person.id) else { fatalError("Missing \(person.id)") }
    var openings = Set<Data>()
    for routine in Dances.all {
        guard let clip = manifest.clips[routine.id] else { fatalError("Missing \(person.id) / \(routine.id)") }
        let count = clip.count
        check(count >= 100, "A complete dance loop is bundled")
        var hashes = Set<Data>()
        for index in 0..<count {
            guard let image = frames.frame(id: person.id, progress: (Double(index) + 0.01) / Double(count), clip: routine.id) else {
                fatalError("Unreadable \(person.id) / \(routine.id) frame \(index)")
            }
            check(image.width == manifest.width && image.height == manifest.height, "Atlas crop dimensions")
            let bytes = digest(image)
            check(bytes.enumerated().contains { $0.offset % 4 == 3 && $0.element > 24 }, "Frame has visible pixels")
            check(bytes[3] == 0, "Transparent background is preserved")
            check(hasClearEdges(image), "Hands, feet, and hair stay inside the rendered frame: \(person.id)/\(routine.id)/\(index)")
            hashes.insert(bytes)
        }
        check(hashes.count > count / 2, "Animation moves instead of repeating a still image")
        let first = frames.frame(id: person.id, progress: 0, clip: routine.id)!
        let wrapped = frames.frame(id: person.id, progress: 1, clip: routine.id)!
        check(digest(first) == digest(wrapped), "Playback wraps at the loop boundary")
        openings.insert(digest(first))
    }
    check(openings.count == Dances.all.count, "Each selected routine has distinct motion")
    check(frames.frame(id: person.id, progress: 0, clip: "missing-dance") == nil, "Unknown routines do not silently play a different dance")
    var reactions = Set<Data>()
    for stage in 1...3 {
        check(manifest.clips["duck\(stage)"] != nil, "A real crouching pose is bundled")
        let image = frames.frame(id: person.id, phase: 0, clip: "duck\(stage)")!
        reactions.insert(digest(image))
    }
    check(reactions.count == 3, "Lid stages have distinct poses")
}
check(frames.frame(id: "missing-person", phase: 0) == nil, "Missing assets fail without crashing")

let clock = Choreographer(bpm: 118, lockedMoveId: nil)
let now = Date().timeIntervalSinceReferenceDate
check(abs(clock.beat(now: now + 1) - clock.beat(now: now) - 118.0 / 60) < 0.001, "Tempo controls time")
clock.paused = true
let frozen = clock.beat(now: now)
check(clock.beat(now: now + 60) == frozen, "Pause freezes animation and preview")
clock.setBPM(172)
check(clock.beat(now: now + 60) == frozen, "Tempo changes while paused preserve the pose")
clock.paused = false
let resumed = Date().timeIntervalSinceReferenceDate
check(abs(clock.beat(now: resumed) - frozen) < 0.03, "Resume does not jump forward")
check(abs(clock.beat(now: resumed + 1) - clock.beat(now: resumed) - 172.0 / 60) < 0.001, "New tempo applies on resume")

// Sample the shared schedule directly: no timers or sleeps are needed.
let danceClock = Choreographer(bpm: 60, lockedMoveId: nil)
let danceNow = Date().timeIntervalSinceReferenceDate
danceClock.setDance("high-kicks", now: danceNow)
check(danceClock.dance(now: danceNow).routine.id == "high-kicks", "Manual dance selection applies immediately")
check(abs(danceClock.dance(now: danceNow + 8).progress - 0.5) < 0.0001, "Clip playback is aligned to its beat duration")
check(danceClock.dance(now: danceNow + 16).progress < 0.0001, "A selected routine loops without changing")
danceClock.setDance("shuffle", now: danceNow)
var elapsed: Double = 0
var visited = Set<String>()
for _ in Dances.all {
    let sample = danceClock.dance(now: danceNow + elapsed + 0.001)
    visited.insert(sample.routine.id)
    check(sample.progress < 0.001, "Shuffle starts each routine at its opening pose")
    let beforeBoundary = danceClock.dance(now: danceNow + elapsed + sample.routine.beats - 0.001)
    check(beforeBoundary.routine.id == sample.routine.id, "Shuffle finishes each full dance before switching")
    let secondReader = danceClock.dance(now: danceNow + elapsed + 0.001)
    check(secondReader.routine.id == sample.routine.id && secondReader.progress == sample.progress, "Preview and squad share one schedule")
    elapsed += sample.routine.beats
}
check(visited == Set(Dances.all.map(\.id)), "Shuffle visits every routine without repeating")
check(danceClock.dance(now: danceNow + elapsed + 0.001).routine.id == danceClock.dance(now: danceNow + 0.001).routine.id, "Shuffle wraps cleanly")
danceClock.paused = true
let heldDance = danceClock.dance(now: danceNow)
danceClock.setBPM(172)
let laterDance = danceClock.dance(now: danceNow + 600)
check(heldDance.routine.id == laterDance.routine.id && heldDance.progress == laterDance.progress, "Pause freezes shuffle and tempo changes preserve it")
danceClock.setDance("step-dip")
check(danceClock.dance(now: danceNow).routine.id == "step-dip" && danceClock.dance(now: danceNow).progress == 0, "Changing routines while paused selects a frozen opening pose")
danceClock.paused = false
check(danceClock.dance(now: Date().timeIntervalSinceReferenceDate).progress < 0.01, "Resume starts from the selected pose")
let previewModel = PanelModel()
previewModel.choreo = danceClock
previewModel.lookId = "carla"
previewModel.updatePreview()
check(previewModel.moveName == "Step & dip" && previewModel.preview != nil, "The live preview names and renders the selected human routine")
danceClock.paused = true
previewModel.updatePreview()
let heldPreview = digest(previewModel.preview!)
previewModel.updatePreview()
check(digest(previewModel.preview!) == heldPreview, "A paused panel preview keeps the same pose")

let suite = "BoogieTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let settings = Settings(defaults: defaults)
check(settings.lookId == "sophia", "New profiles use a realistic companion")
check(settings.danceId == "shuffle", "New profiles shuffle the realistic dances")
settings.danceId = "high-kicks"
settings.moveId = "disco"
check(Settings(defaults: defaults).danceId == "high-kicks", "Dance selection persists")
check(settings.moveId == "disco", "Realistic dances and pixel moves keep separate preferences")
defaults.set("retired-dance", forKey: "realisticDance")
check(settings.danceId == "shuffle", "Unknown dance preferences recover safely")
for person in Companions.people {
    settings.lookId = person.id
    check(Settings(defaults: defaults).lookId == person.id, "Every scanned character can be selected and restored")
}
settings.lookId = "manuel"
check(Settings(defaults: defaults).lookId == "manuel", "Character selection persists")
settings.lookId = "boogie"
check(settings.lookId == "boogie", "Pixel classics remain selectable")
defaults.set("unavailable", forKey: "character")
check(settings.lookId == "sophia", "Unknown persisted characters recover safely")
defaults.removePersistentDomain(forName: suite)

let crossover = Crossover()
let dark = crossover.update(now: 10, readout: SensorReadout(tilt: 0.3, lid: 30, lux: 0))
check(dark.duck == 3, "Closing the lid selects the deepest crouch")
check(dark.lights, "Darkness enables evening glow")
let size = Companions.size(for: "sophia", scale: 5)
check(size == CGSize(width: 240, height: 320), "People retain their portrait aspect ratio")
check(Companions.size(for: "boogie", scale: 5) == CGSize(width: 180, height: 180), "Pixel geometry is retained")
// Exercise the actual AppDelegate and NSPanel lifecycle using an isolated
// preferences suite. This does not install the app or alter the user's settings.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let smokeSuite = "BoogieSmoke.\(UUID().uuidString)"
let smokeDefaults = UserDefaults(suiteName: smokeSuite)!
let smokeSettings = Settings(defaults: smokeDefaults)
smokeSettings.surf = false
smokeSettings.lightsMode = "off"
let delegate = AppDelegate(settings: smokeSettings)
app.delegate = delegate
delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
func dancers() -> [DancerWindow] { app.windows.compactMap { $0 as? DancerWindow }.filter { $0.isVisible } }
func settle(_ seconds: Double = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
settle()
check(dancers().count == 1, "Launch creates one companion")
check(dancers().first?.dancer.characterID == "sophia", "Launch shows the selected human")
check(dancers().first?.dancer.layer?.sublayers?.first?.contents != nil, "Native layer receives animation frames")
delegate.setLook("manuel")
settle()
check(dancers().first?.dancer.characterID == "manuel", "Switching people rebuilds the native window")
delegate.setSquad(3)
settle()
check(dancers().count == 3, "Trio creates three companions")
check(Set(dancers().map { $0.dancer.characterID }) == Set(["manuel", "carla", "nathan"]), "A trio uses three distinct scanned people")
for person in Companions.people {
    delegate.setLook(person.id)
    settle()
    check(dancers().contains { $0.dancer.characterID == person.id && $0.dancer.layer?.sublayers?.first?.contents != nil }, "Every companion renders in the native window")
}
for routine in Dances.all {
    delegate.setDance(routine.id)
    settle()
    check(smokeSettings.danceId == routine.id, "Dance selection reaches the native app and persists")
    check(dancers().allSatisfy { $0.dancer.layer?.sublayers?.first?.contents != nil }, "Every dancer receives the selected routine")
}
delegate.setHidden(true)
check(dancers().isEmpty, "Hide removes every companion from view")
delegate.setHidden(false)
check(dancers().count == 3, "Show restores the group")
delegate.setScale(3)
settle()
check(dancers().allSatisfy { $0.frame.size == CGSize(width: 144, height: 192) }, "Resizing preserves people proportions")
delegate.setPaused(true)
check(smokeSettings.paused, "Pause persists")
delegate.setPaused(false)
delegate.setBPM(140)
check(smokeSettings.bpm == 140, "Tempo control persists")
if let window = dancers().first {
    window.setFrameOrigin(CGPoint(x: window.frame.minX, y: window.frame.minY + 150))
    window.dancer.onDragEnd?(window.frame.origin)
    settle(0.9)
    let floor = window.screen!.visibleFrame.minY - Companions.footInset(for: window.dancer.characterID, scale: 3)
    check(abs(window.frame.minY - floor) < 2, "Dropping a person lands them on the Dock")
    window.dancer.onClick?()
    settle()
    check((window.dancer.layer?.sublayers?.last?.sublayers?.count ?? 0) > 0, "Click feedback produces hearts")
}
delegate.snapToDock()
delegate.setLook("boogie")
settle()
check(dancers().allSatisfy { !Companions.find($0.dancer.characterID).realistic }, "Classic squads remain available")
check(dancers().allSatisfy { $0.dancer.layer?.contents != nil }, "Classic sprite rendering still works")
delegate.setHidden(true)
smokeDefaults.removePersistentDomain(forName: smokeSuite)
print("Passed \(checks) checks: every atlas frame, all dance routines, shuffle synchronization, loop wrap, crouches, pause/tempo, settings, sensors, and native app lifecycle.")
