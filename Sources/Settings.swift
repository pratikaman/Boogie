import Foundation
import CoreGraphics

/// UserDefaults-backed preferences.
final class Settings {
    static let shared = Settings()
    private let d: UserDefaults

    init(defaults: UserDefaults = .standard) { d = defaults }

    var paused: Bool {
        get { d.bool(forKey: "paused") }
        set { d.set(newValue, forKey: "paused") }
    }
    var hidden: Bool {
        get { d.bool(forKey: "hidden") }
        set { d.set(newValue, forKey: "hidden") }
    }
    var bpm: Int {
        get { let v = d.integer(forKey: "bpm"); return v == 0 ? 118 : v }
        set { d.set(newValue, forKey: "bpm") }
    }
    /// Screen points per sprite pixel.
    var scale: Int {
        get { let v = d.integer(forKey: "scale"); return v == 0 ? 5 : v }
        set { d.set(newValue, forKey: "scale") }
    }
    /// Rendered people by default; the legacy pixel cast remains selectable.
    var lookId: String {
        get { Companions.find(d.string(forKey: "character") ?? "sophia").id }
        set { d.set(newValue, forKey: "character") }
    }
    var fitId: String {
        get { d.string(forKey: "fit") ?? "raver" }
        set { d.set(newValue, forKey: "fit") }
    }
    var skinId: String {
        get { d.string(forKey: "skin") ?? "fair" }
        set { d.set(newValue, forKey: "skin") }
    }
    /// "shuffle" or a move id.
    var moveId: String {
        get { d.string(forKey: "move") ?? "shuffle" }
        set { d.set(newValue, forKey: "move") }
    }
    /// Kept separate from the original pixel cast's move preference.
    var danceId: String {
        get { Dances.selection(d.string(forKey: "realisticDance") ?? "shuffle") }
        set { d.set(Dances.selection(newValue), forKey: "realisticDance") }
    }
    var squad: Int {
        get { max(1, d.integer(forKey: "squad")) }
        set { d.set(max(1, newValue), forKey: "squad") }
    }

    /// An explicit lineup can mix casts and repeat dancers. Nil uses the presets.
    var customLineup: [String]? {
        get {
            guard let saved = d.stringArray(forKey: "customLineup") else { return nil }
            let available = Set((Companions.people + Companions.classics + Companions.customs).map(\.id))
            let remaining = saved.filter { available.contains($0) }
            return remaining.isEmpty ? [lookId] : remaining
        }
        set {
            if let newValue { d.set(newValue, forKey: "customLineup") }
            else { d.removeObject(forKey: "customLineup") }
        }
    }

    var dancerIDs: [String] {
        if let customLineup { return customLineup }
        let roster = Companions.roster(for: lookId)
        let first = roster.firstIndex { $0.id == lookId } ?? 0
        return (0..<squad).map { roster[(first + $0) % roster.count].id }
    }

    // Sensor crossovers.
    var surf: Bool {
        get { d.object(forKey: "surf") == nil ? true : d.bool(forKey: "surf") }
        set { d.set(newValue, forKey: "surf") }
    }
    var duck: Bool {
        get { d.object(forKey: "duck") == nil ? true : d.bool(forKey: "duck") }
        set { d.set(newValue, forKey: "duck") }
    }
    /// auto | on | off
    var lightsMode: String {
        get { d.string(forKey: "lights") ?? "auto" }
        set { d.set(newValue, forKey: "lights") }
    }
    var tiltAxis: Int {
        get { d.integer(forKey: "tiltAxis") }
        set { d.set(newValue, forKey: "tiltAxis") }
    }
    var tiltSign: Double {
        get { d.object(forKey: "tiltSign") == nil ? 1 : d.double(forKey: "tiltSign") }
        set { d.set(newValue, forKey: "tiltSign") }
    }

    /// Where the user dragged dancer `i` (window origin), if they moved it off the Dock.
    func position(_ i: Int) -> CGPoint? {
        guard let s = d.string(forKey: "pos.\(i)") else { return nil }
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }

    func setPosition(_ i: Int, _ p: CGPoint?) {
        if let p { d.set("\(p.x),\(p.y)", forKey: "pos.\(i)") } else { d.removeObject(forKey: "pos.\(i)") }
    }

    func clearPositions() {
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("pos.") {
            d.removeObject(forKey: key)
        }
    }
}
