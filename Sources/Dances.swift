import Foundation

struct DanceRoutine: Identifiable {
    let id: String
    let name: String
    let beats: Double
}

/// Each routine has matching rendered clips for every person.
enum Dances {
    static let all = [
        DanceRoutine(id: "dance", name: "Easy groove", beats: 24),
        DanceRoutine(id: "high-kicks", name: "High kicks", beats: 16),
        DanceRoutine(id: "step-dip", name: "Step & dip", beats: 16)
    ]
    static func find(_ id: String) -> DanceRoutine? { all.first { $0.id == id } }
    static func selection(_ id: String) -> String { find(id) == nil ? "shuffle" : id }
}

struct DanceSample {
    let routine: DanceRoutine
    /// Position within this routine, from zero up to (but excluding) one.
    let progress: Double
}
