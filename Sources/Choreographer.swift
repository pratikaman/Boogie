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
    private var pausedBeat: Double?
    private(set) var danceId: String
    private var danceStartBeat: Double = 0
    private var danceOrder = [Dances.all[0]] + Array(Dances.all.dropFirst()).shuffled()
    var paused: Bool {
        get { pausedBeat != nil }
        set {
            let now = Date().timeIntervalSinceReferenceDate
            if newValue {
                if pausedBeat == nil { pausedBeat = beat(now: now) }
            } else if let frozen = pausedBeat {
                t0 = now - frozen * 60 / Double(bpm)
                pausedBeat = nil
            }
        }
    }
    /// How many beats each move lasts in shuffle mode.
    var beatsPerMove: Double = 8

    init(bpm: Int, lockedMoveId: String?, danceId: String = "shuffle") {
        self.bpm = bpm
        self.t0 = Date().timeIntervalSinceReferenceDate
        self.lockedMoveId = lockedMoveId
        self.currentMove = lockedMoveId.flatMap(Moves.named) ?? Moves.bop
        self.danceId = Dances.selection(danceId)
    }

    func setDance(_ id: String, now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        danceId = Dances.selection(id)
        danceStartBeat = beat(now: now)
        if danceId == "shuffle" { danceOrder.shuffle() }
    }

    /// Pure sampling keeps the preview and every member of the squad in sync.
    /// Shuffle visits each routine once before repeating, at whole-loop boundaries.
    func dance(now: TimeInterval) -> DanceSample {
        let elapsed = max(0, beat(now: now) - danceStartBeat)
        let order = Dances.find(danceId).map { [$0] } ?? danceOrder
        let cycle = order.reduce(0) { $0 + $1.beats }
        var position = elapsed.truncatingRemainder(dividingBy: cycle)
        for routine in order {
            if position < routine.beats {
                return DanceSample(routine: routine, progress: position / routine.beats)
            }
            position -= routine.beats
        }
        return DanceSample(routine: order[0], progress: 0)
    }

    var currentMoveName: String { paused ? Moves.idle.name : currentMove.name }

    func beat(now: TimeInterval) -> Double {
        pausedBeat ?? (now - t0) * Double(bpm) / 60
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
