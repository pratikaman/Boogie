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

let frames = CharacterFrames(root: URL(fileURLWithPath: CommandLine.arguments[1]))
for person in Companions.people {
    guard let manifest = frames.manifest(person.id) else { fatalError("Missing \(person.id)") }
    let count = manifest.clips["dance"]!.count
    check(count >= 100, "A complete dance loop is bundled")
    var hashes = Set<Data>()
    for index in 0..<count {
        guard let image = frames.frame(id: person.id, phase: Double(index) / manifest.fps + 0.00001) else {
            fatalError("Unreadable \(person.id) frame \(index)")
        }
        check(image.width == manifest.width && image.height == manifest.height, "Atlas crop dimensions")
        let bytes = digest(image)
        check(bytes.enumerated().contains { $0.offset % 4 == 3 && $0.element > 24 }, "Frame has visible pixels")
        check(bytes[3] == 0, "Transparent background is preserved")
        hashes.insert(bytes)
    }
    check(hashes.count > count / 2, "Animation moves instead of repeating a still image")
    let first = frames.frame(id: person.id, phase: 0)!
    let wrapped = frames.frame(id: person.id, phase: Double(count) / manifest.fps)!
    check(digest(first) == digest(wrapped), "Playback wraps at the loop boundary")
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

let suite = "BoogieTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let settings = Settings(defaults: defaults)
check(settings.lookId == "sophia", "New profiles use a realistic companion")
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
check(Set(dancers().map { $0.dancer.characterID }) == Set(["sophia", "manuel"]), "Realistic squads use only real people")
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
print("Passed \(checks) checks: every atlas frame, animation diversity, loop wrap, crouches, pause/tempo, settings, sensors, and native app lifecycle.")
