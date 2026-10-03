import AppKit
import SwiftUI

let app = NSApplication.shared

func argument(_ flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

if let output = argument("--prepare-video"), let source = argument("--video") {
    Task {
        do {
            let dance = try await VideoDance.load(URL(fileURLWithPath: source))
            try JSONEncoder().encode(dance).write(to: URL(fileURLWithPath: output), options: .atomic)
            print("wrote \(dance.frames.count) frames at 24 fps to \(output)")
            exit(0)
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    RunLoop.main.run()
    exit(0)
}

// Explicit developer utilities for checking the image-model pipeline.
if let output = argument("--generate-likeness"), let source = argument("--image") {
    do {
        let image = try PhotoImport.load(URL(fileURLWithPath: source))
        let portrait = try LikenessAI.generate(image: image, stage: .portrait, job: AvatarGeneration(timeout: 600))
        guard let data = NSBitmapImageRep(cgImage: portrait).representation(using: .png, properties: [:]) else { throw CreatorError.image }
        try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        print("wrote likeness to \(output)")
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    exit(0)
}
if let output = argument("--prepare-dance"), let source = argument("--sheet") {
    do {
        let image = try LikenessAI.loadGenerated(URL(fileURLWithPath: source))
        let dance = try GeneratedDance.fromSheet(image)
        try JSONEncoder().encode(dance).write(to: URL(fileURLWithPath: output), options: .atomic)
        print("wrote dance frames to \(output)")
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    exit(0)
}
if let output = argument("--render-generated-frame"), let source = argument("--dance-json") {
    do {
        let dance = try JSONDecoder().decode(GeneratedDance.self, from: Data(contentsOf: URL(fileURLWithPath: source))).validated()
        guard let frame = GeneratedDanceFrames.shared.frame(id: "render", dance: dance, beat: Double(argument("--beat") ?? "0") ?? 0),
              let data = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:]) else { throw CreatorError.image }
        try data.write(to: URL(fileURLWithPath: output))
        print("wrote pose to \(output)")
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    exit(0)
}

// Explicit developer utilities. Generation invokes the selected signed-in CLI;
// rendering a saved design is local and deterministic.
if let output = argument("--generate-avatar"), let source = argument("--image") {
    do {
        let image = try PhotoImport.load(URL(fileURLWithPath: source))
        let provider = AvatarProvider(rawValue: argument("--provider") ?? "codex") ?? .codex
        let avatar = try AvatarGeneration().generate(image: image, provider: provider)
        try JSONEncoder().encode(avatar).write(to: URL(fileURLWithPath: output), options: .atomic)
        print("wrote avatar design to \(output)")
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    exit(0)
}
if let output = argument("--render-avatar") {
    do {
        let avatar = try argument("--avatar-design").map { try JSONDecoder().decode(AvatarDesign.self, from: Data(contentsOf: URL(fileURLWithPath: $0))) } ?? .example
        let scene = try AvatarScene(design: avatar)
        let motion = CutoutMotion(rawValue: argument("--motion") ?? "bounce") ?? .bounce
        guard let image = scene.frame(motion: motion, beat: Double(argument("--beat") ?? "0.6") ?? 0.6),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw AvatarError.unavailable }
        try data.write(to: URL(fileURLWithPath: output))
        print("wrote 3D avatar to \(output)")
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-creator"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        let model = CreatorModel()
        if let p = CommandLine.arguments.firstIndex(of: "--image"), p + 1 < CommandLine.arguments.count {
            let url = URL(fileURLWithPath: CommandLine.arguments[p + 1])
            model.load(url)
            let deadline = Date().addingTimeInterval(45)
            while model.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            guard !model.busy, model.image != nil else {
                fputs("\(model.error ?? "Image import timed out.")\n", stderr); exit(1)
            }
        }
        if let path = argument("--avatar-design") {
            do {
                let avatar = try JSONDecoder().decode(AvatarDesign.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
                try model.acceptAvatar(avatar)
                if model.name.isEmpty { model.name = "My avatar" }
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let path = argument("--likeness") {
            do {
                try model.acceptLikeness(LikenessAI.loadGenerated(URL(fileURLWithPath: path)))
                if model.name.isEmpty { model.name = "My dancer" }
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let path = argument("--dance-json") {
            do {
                try model.acceptDance(JSONDecoder().decode(GeneratedDance.self, from: Data(contentsOf: URL(fileURLWithPath: path))))
                if model.name.isEmpty { model.name = "My dancer" }
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        // Native text fields, segmented controls, and drop targets need AppKit
        // rendering; SwiftUI ImageRenderer replaces them with placeholders.
        let content = NSHostingView(rootView: CreatorView(model: model, chooseImage: {}, save: {}, cancel: {}, delete: {}, staticRender: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 740), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = content
        content.frame = NSRect(x: 0, y: 0, width: 720, height: 740)
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
        catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        print("wrote \(CommandLine.arguments[i + 1]) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
    }
    exit(0)
}

// `Boogie --render-panel out.png` renders the control panel offscreen with
// sample data, for README screenshots and layout checks.
if let i = CommandLine.arguments.firstIndex(of: "--render-panel"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        // Documentation previews can omit the user's private custom photos.
        if CommandLine.arguments.contains("--sample-library") {
            CustomDancerStore.shared = CustomDancerStore(root: FileManager.default.temporaryDirectory
                .appendingPathComponent("BoogiePreview-\(UUID().uuidString)"))
        }
        let model = PanelModel.sample()
        if let c = CommandLine.arguments.firstIndex(of: "--character"), c + 1 < CommandLine.arguments.count {
            model.lookId = CommandLine.arguments[c + 1]
            model.updatePreview()
        }
        if let l = CommandLine.arguments.firstIndex(of: "--lineup"), l + 1 < CommandLine.arguments.count {
            let ids = CommandLine.arguments[l + 1].split(separator: ",").map { Companions.find(String($0)).id }
            if let first = ids.first {
                model.lineup = ids
                model.squad = ids.count
                model.customCompany = true
                model.lookId = first
                model.updatePreview()
            }
        }
        if let d = CommandLine.arguments.firstIndex(of: "--dance"), d + 1 < CommandLine.arguments.count,
           let routine = Dances.find(CommandLine.arguments[d + 1]), Companions.find(model.lookId).realistic {
            model.danceId = routine.id
            model.moveName = routine.name
            model.preview = CharacterFrames.shared.frame(id: model.lookId, progress: 0.35, clip: routine.id)
        }
        if CommandLine.arguments.contains("--paused") { model.paused = true }
        if CommandLine.arguments.contains("--hidden") { model.hidden = true }
        let renderer = ImageRenderer(content: PanelView(model: model, showPreferences: CommandLine.arguments.contains("--preferences")))
        renderer.scale = 2
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                print("wrote \(CommandLine.arguments[i + 1]) \(cg.width)x\(cg.height)")
            }
        }
    }
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
