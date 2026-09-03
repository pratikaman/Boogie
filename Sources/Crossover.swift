import Foundation
import CoreGraphics

/// What the sensors are doing to the dancer this frame.
struct Ambience {
    var lights = false        // club lights on
    var duck = 0              // 0 none, 1 brace, 2 crouch, 3 flat
    var surfDir = 0           // -1 left, +1 right, 0 not surfing
    var slideDx: CGFloat = 0  // points to move the window this frame
    var celebrate = false     // the lid just came back up
}

/// Turns sensor readings into behaviour: tilt slides her along the Dock with
/// a little physics, a closing lid makes her duck in stages, darkness turns
/// the club lights on with hysteresis.
final class Crossover {
    var surfEnabled = true
    var duckEnabled = true
    var lightsMode = "auto"   // auto | on | off

    private(set) var surfing = false
    private(set) var lights = false
    private(set) var duckStage = 0
    private var velocity: CGFloat = 0
    private var darkLatch = false
    private var lastTime: TimeInterval = 0

    static let deadzone = 0.05      // g
    static let gain: CGFloat = 1600 // points/s² per g
    static let maxSpeed: CGFloat = 900

    func update(now: TimeInterval, readout: SensorReadout) -> Ambience {
        let dt = lastTime == 0 ? 1.0 / 30 : min(0.1, now - lastTime)
        lastTime = now
        var a = Ambience()

        if let lux = readout.lux {
            if lux < 6 { darkLatch = true } else if lux > 18 { darkLatch = false }
        }
        lights = lightsMode == "on" || (lightsMode == "auto" && darkLatch)
        a.lights = lights

        let stage = (duckEnabled && readout.lid != nil) ? Self.stage(readout.lid!, previous: duckStage) : 0
        if duckStage >= 2 && stage == 0 { a.celebrate = true }
        duckStage = stage
        a.duck = stage

        let tilt = (surfEnabled && stage == 0) ? (readout.tilt ?? 0) : 0
        let active = abs(tilt) > Self.deadzone
        if active { velocity += CGFloat(tilt) * Self.gain * CGFloat(dt) }
        velocity *= CGFloat(exp(-dt / 0.5))
        velocity = max(-Self.maxSpeed, min(Self.maxSpeed, velocity))
        if !active && abs(velocity) < 15 { velocity = 0 }
        surfing = active || velocity != 0
        if surfing {
            a.surfDir = velocity != 0 ? (velocity > 0 ? 1 : -1) : (tilt > 0 ? 1 : -1)
            a.slideDx = velocity * CGFloat(dt)
        }
        return a
    }

    /// She hit the edge of the screen.
    func bounce() { velocity = -velocity * 0.35 }

    /// Lid angle -> duck stage, with 2° of hysteresis so she doesn't twitch at a boundary.
    private static func stage(_ angle: Double, previous: Int) -> Int {
        let bounds = [85.0, 60.0, 40.0]
        var s = 0
        for k in 1...3 {
            let threshold = bounds[k - 1] + (previous >= k ? 2 : -2)
            if angle < threshold { s = k }
        }
        return s
    }
}
