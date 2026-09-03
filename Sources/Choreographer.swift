import Foundation

/// The shared beat clock and move picker. Every dancer reads from the same
/// choreographer so a squad stays in sync.
final class Choreographer {
    private(set) var bpm: Int
    private var t0: TimeInterval          // wall time of beat zero
    private var currentMove: Move
    private var moveStartBeat: Double = 0
    /// nil = shuffle through every move, otherwise stick to this one.
    var lockedMoveId: String? {
        didSet { if let id = lockedMoveId, let m = Moves.named(id) { switchTo(m, at: beat(now: Date().timeIntervalSinceReferenceDate)) } }
    }
    var paused = false
    /// How many beats each move lasts in shuffle mode.
    var beatsPerMove: Double = 8

    init(bpm: Int, lockedMoveId: String?) {
        self.bpm = bpm
        self.t0 = Date().timeIntervalSinceReferenceDate
        self.lockedMoveId = lockedMoveId
        self.currentMove = lockedMoveId.flatMap(Moves.named) ?? Moves.bop
    }

    var currentMoveName: String { paused ? Moves.idle.name : currentMove.name }

    func beat(now: TimeInterval) -> Double {
        (now - t0) * Double(bpm) / 60
    }

    /// Change tempo without the beat jumping.
    func setBPM(_ newBPM: Int) {
        let now = Date().timeIntervalSinceReferenceDate
        let b = beat(now: now)
        bpm = newBPM
        t0 = now - b * 60 / Double(newBPM)
    }

    private func switchTo(_ move: Move, at beat: Double) {
        currentMove = move
        moveStartBeat = floor(beat)
    }

    /// The move to render right now and how many beats into it we are.
    func current(now: TimeInterval) -> (move: Move, beat: Double) {
        let b = beat(now: now)
        if paused { return (Moves.idle, b) }
        if lockedMoveId == nil, b - moveStartBeat >= beatsPerMove {
            var next = Moves.all.randomElement()!
            while next.id == currentMove.id { next = Moves.all.randomElement()! }
            switchTo(next, at: b)
        }
        return (currentMove, b - moveStartBeat)
    }
}
