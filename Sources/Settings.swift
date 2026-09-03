import Foundation
import CoreGraphics

/// UserDefaults-backed preferences.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

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
    var squad: Int {
        get { let v = d.integer(forKey: "squad"); return v == 0 ? 1 : v }
        set { d.set(newValue, forKey: "squad") }
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
        for i in 0..<8 { d.removeObject(forKey: "pos.\(i)") }
    }
}
