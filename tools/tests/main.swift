import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

var checks = 0
func check(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
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

try MainActor.assumeIsolated {
    // Imports and persistence use an isolated library, never the user's collection.
    let customRoot = FileManager.default.temporaryDirectory.appendingPathComponent("BoogieCustomTests-\(UUID().uuidString)")
    let originalStore = CustomDancerStore.shared
    CustomDancerStore.shared = CustomDancerStore(root: customRoot)
    defer {
        CustomDancerStore.shared = originalStore
        try? FileManager.default.removeItem(at: customRoot)
    }
    let customStore = CustomDancerStore.shared
    let fixture = CutoutAnimation.context(width: 160, height: 240)!
    fixture.setFillColor(NSColor.systemOrange.cgColor)
    fixture.fill(CGRect(x: 55, y: 40, width: 50, height: 115))
    fixture.setFillColor(NSColor.systemBlue.cgColor)
    fixture.fillEllipse(in: CGRect(x: 45, y: 155, width: 70, height: 60))
    let sourceImage = fixture.makeImage()!
    let normalized = try PhotoImport.normalize(sourceImage)
    check(normalized.width == 384 && normalized.height == 512, "Imported art has bounded, consistent dimensions")
    check(hasClearEdges(normalized), "Imported art reserves transparent motion margins")
    let transparent = CutoutAnimation.context(width: 100, height: 100)!.makeImage()!
    do { _ = try PhotoImport.normalize(transparent); check(false, "Empty images must be rejected") }
    catch { check(error is CreatorError, "Transparent image import has an actionable error") }
    do { _ = try customStore.save(name: "  ", motion: .bounce, image: normalized); check(false, "Empty names must fail") }
    catch { check(customStore.dancers.isEmpty, "A failed save leaves the library unchanged") }
    let custom = try customStore.save(name: "  Marmalade  ", motion: .bounce, image: normalized)
    check(custom.name == "Marmalade", "Names are trimmed before saving")
    check(Companions.find(custom.id).custom, "Custom dancers are discoverable by persisted ID")
    check(Companions.size(for: custom.id, scale: 5) == CGSize(width: 240, height: 320), "Cutouts share image-based window geometry")
    let importedFile = customRoot.appendingPathComponent("source.png")
    try custom.png.write(to: importedFile)
    let importedImage = try PhotoImport.load(importedFile)
    check(importedImage.width <= 1024 && importedImage.height <= 1024, "Image imports decode at bounded resolution")
    try FileManager.default.removeItem(at: importedFile)
    // EXIF rotation must be applied before fitting a phone photo to the stage.
    let orientedFile = customRoot.appendingPathComponent("rotated.jpg")
    let orientedDestination = CGImageDestinationCreateWithURL(orientedFile as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(orientedDestination, sourceImage, [kCGImagePropertyOrientation: 6] as CFDictionary)
    check(CGImageDestinationFinalize(orientedDestination), "The oriented import fixture is valid")
    let orientedImage = try PhotoImport.load(orientedFile)
    check(orientedImage.width == sourceImage.height && orientedImage.height == sourceImage.width, "Phone photo EXIF orientation is applied")
    let oversizedFile = customRoot.appendingPathComponent("large.png")
    FileManager.default.createFile(atPath: oversizedFile.path, contents: nil)
    let oversizedHandle = try FileHandle(forWritingTo: oversizedFile)
    try oversizedHandle.truncate(atOffset: 30_000_001)
    try oversizedHandle.close()
    do { _ = try PhotoImport.load(oversizedFile); check(false, "Oversized input must fail") }
    catch { check(error is CreatorError, "Oversized files fail before decoding") }
    let reloaded = CustomDancerStore(root: customRoot)
    check(reloaded.find(custom.id)?.name == custom.name && reloaded.image(custom.id) != nil, "Custom dancers survive restart and source removal")
    let originalPixels = digest(reloaded.image(custom.id)!)
    try customStore.setMotion(.sway, for: custom.id)
    check(CustomDancerStore(root: customRoot).find(custom.id)?.motion == .sway, "Custom motion changes persist")
    check(digest(customStore.image(custom.id)!) == originalPixels, "Changing motion preserves the imported artwork")
    let renamed = try customStore.save(id: custom.id, name: "Marmalade II", motion: .twirl, image: normalized)
    check(renamed.id == custom.id && customStore.dancers.count == 1, "Editing updates the existing dancer without duplicating it")
    let secondCustom = try customStore.save(name: "Pepper", motion: .sway, image: normalized)
    check(Companions.roster(for: custom.id).count == 2, "Custom squads cycle through the saved custom cast")
    let invalidFile = customRoot.appendingPathComponent("broken.json")
    try Data("not json".utf8).write(to: invalidFile)
    check(CustomDancerStore(root: customRoot).dancers.count == 2, "A damaged record does not hide valid saved dancers")
    do { _ = try PhotoImport.load(invalidFile); check(false, "Non-image input must fail") }
    catch { check(true, "Unsupported input fails without crashing") }
    let blockedRoot = customRoot.appendingPathComponent("not-a-directory")
    try Data().write(to: blockedRoot)
    let blockedStore = CustomDancerStore(root: blockedRoot)
    do { _ = try blockedStore.save(name: "Unsaved", motion: .bounce, image: normalized); check(false, "An unwritable library must fail") }
    catch { check(blockedStore.dancers.isEmpty, "Storage errors never report a dancer as saved") }
    for motion in CutoutMotion.allCases {
        var poses = Set<Data>()
        for step in 0..<32 {
            let image = CutoutAnimation.frame(image: normalized, motion: motion, beat: Double(step) / 8)!
            poses.insert(digest(image))
            check(hasClearEdges(image), "Cutout motion stays within the transparent canvas")
        }
        check(poses.count >= 8, "\(motion.name) visibly animates (\(poses.count) distinct sampled poses)")
        let opening = CutoutAnimation.frame(image: normalized, motion: motion, beat: 0)!
        let wrapped = CutoutAnimation.frame(image: normalized, motion: motion, beat: 4)!
        check(digest(opening) == digest(wrapped), "Cutout motion loops without a seam")
    }

    // AI returns validated geometry descriptions. These tests never contact an AI service.
    let avatarJSON = try JSONEncoder().encode(AvatarDesign.example)
    let decodedCodex = try AvatarGeneration.decode(avatarJSON, provider: .codex)
    check(decodedCodex == .example, "Codex structured output is accepted")
    let claudeEnvelope = try JSONSerialization.data(withJSONObject: ["is_error": false, "structured_output": JSONSerialization.jsonObject(with: avatarJSON)])
    let decodedClaude = try AvatarGeneration.decode(claudeEnvelope, provider: .claude)
    check(decodedClaude == .example, "Claude's structured-output envelope is accepted")
    var streamedEnvelope = try JSONSerialization.jsonObject(with: claudeEnvelope) as! [String: Any]
    streamedEnvelope["type"] = "result"
    let streamedData = Data("{\"type\":\"system\",\"subtype\":\"init\"}\n".utf8) + (try JSONSerialization.data(withJSONObject: streamedEnvelope)) + Data([10])
    let decodedStream = try AvatarGeneration.decode(streamedData, provider: .claude)
    check(decodedStream == .example, "Claude image requests decode the final result from its required JSON stream")
    var invalidAvatar = try JSONSerialization.jsonObject(with: avatarJSON) as! [String: Any]
    invalidAvatar["bodyWidth"] = 1000
    do { _ = try AvatarGeneration.decode(JSONSerialization.data(withJSONObject: invalidAvatar), provider: .codex); check(false, "Out-of-bounds geometry must fail") }
    catch { check(true, "Untrusted AI geometry is bounded before rendering") }
    invalidAvatar["bodyWidth"] = 1
    invalidAvatar["skinColor"] = "not-a-color"
    do { _ = try AvatarGeneration.decode(JSONSerialization.data(withJSONObject: invalidAvatar), provider: .codex); check(false, "Invalid colors must fail") }
    catch { check(true, "Invalid material colors are rejected") }
    do { _ = try AvatarGeneration.decode(Data("{\"is_error\":true,\"result\":\"Not logged in\"}".utf8), provider: .claude); check(false, "Provider failures must not become avatars") }
    catch { check(error.localizedDescription.contains("Sign in"), "Missing Claude sign-in produces recovery guidance") }

    let responseFile = customRoot.appendingPathComponent("ai-response.json")
    try avatarJSON.write(to: responseFile)
    let mockCLI = customRoot.appendingPathComponent("mock-codex")
    let mockScript = """
    #!/bin/sh
    while [ "$#" -gt 0 ]; do
        if [ "$1" = "--output-last-message" ]; then shift; result_path="$1"; fi
        shift
    done
    /bin/cp '\(responseFile.path)' "$result_path"
    """
    try Data(mockScript.utf8).write(to: mockCLI)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mockCLI.path)
    let mockResult = try AvatarGeneration().generate(image: normalized, provider: .codex, executable: mockCLI)
    check(mockResult == .example, "The full CLI process, image staging and response pipeline works")
    let claudeResponseFile = customRoot.appendingPathComponent("claude-response.jsonl")
    try streamedData.write(to: claudeResponseFile)
    let mockClaude = customRoot.appendingPathComponent("mock-claude")
    try Data("#!/bin/sh\n/bin/cat '\(claudeResponseFile.path)'\n".utf8).write(to: mockClaude)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mockClaude.path)
    let mockClaudeResult = try AvatarGeneration().generate(image: normalized, provider: .claude, executable: mockClaude)
    check(mockClaudeResult == .example, "The Claude image input and streamed response pipeline works")
    let cancelledJob = AvatarGeneration()
    cancelledJob.cancel()
    do { _ = try cancelledJob.generate(image: normalized, provider: .codex, executable: mockCLI); check(false, "Cancelled generation must not run") }
    catch { check(error.localizedDescription.contains("cancelled"), "Cancellation prevents subprocess launch") }
    let slowCLI = customRoot.appendingPathComponent("slow-cli")
    try Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8).write(to: slowCLI)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: slowCLI.path)
    do { _ = try AvatarGeneration(timeout: 0.1).generate(image: normalized, provider: .codex, executable: slowCLI); check(false, "Slow processes must time out") }
    catch { check(error.localizedDescription.contains("too long"), "Timeout stops the CLI and explains how to retry") }

    // The new image-model flow accepts generated PNGs, never geometry or arbitrary file paths.
    let generatedRoot = customRoot.appendingPathComponent("generated-images")
    try FileManager.default.createDirectory(at: generatedRoot, withIntermediateDirectories: true)
    let generatedPNG = generatedRoot.appendingPathComponent("likeness.png")
    try custom.png.write(to: generatedPNG)
    let imageResult = try JSONSerialization.data(withJSONObject: ["image_path": generatedPNG.path])
    let allowedResult = try LikenessAI.resultURL(imageResult, roots: [generatedRoot], after: Date())
    check(allowedResult == generatedPNG.resolvingSymlinksInPath(), "Image results resolve within the allowed generated directory")
    do { _ = try LikenessAI.resultURL(imageResult, roots: [generatedRoot.appendingPathComponent("different")], after: Date()); check(false, "Arbitrary paths must be rejected") }
    catch { check(true, "Model output cannot make Boogie read unrelated image files") }
    let escapedPNG = generatedRoot.appendingPathComponent("linked.png")
    try FileManager.default.createSymbolicLink(at: escapedPNG, withDestinationURL: importedFile)
    do {
        let escapedResult = try JSONSerialization.data(withJSONObject: ["image_path": escapedPNG.path])
        _ = try LikenessAI.resultURL(escapedResult, roots: [generatedRoot], after: Date())
        check(false, "Symlink escapes must fail")
    } catch { check(true, "Image paths cannot escape the allowed directory through symlinks") }
    do { _ = try LikenessAI.resultURL(imageResult, roots: [generatedRoot], after: Date().addingTimeInterval(20)); check(false, "Old images must fail") }
    catch { check(true, "Stale image paths cannot be presented as fresh generation") }
    do { _ = try LikenessAI.resultURL(Data("{\"error\":\"image_generation_unavailable\"}".utf8), roots: [generatedRoot], after: Date()); check(false, "Missing image tools must fail") }
    catch { check(error.localizedDescription.contains("image generation"), "Unavailable image generation has recovery guidance") }
    try imageResult.write(to: responseFile)
    let generatedByMock = try LikenessAI.generate(image: sourceImage, stage: .portrait, job: AvatarGeneration(), executable: mockCLI, outputRoots: [generatedRoot])
    check(generatedByMock.width == 384, "The image CLI staging, result parsing and bounded PNG loading work together")
    let cancelledImageJob = AvatarGeneration()
    cancelledImageJob.cancel()
    do { _ = try LikenessAI.generate(image: sourceImage, stage: .portrait, job: cancelledImageJob, executable: mockCLI, outputRoots: [generatedRoot]); check(false, "Cancelled image jobs must not launch") }
    catch { check(error.localizedDescription.contains("cancelled"), "Image generation uses the cancellable process runner") }

    // Build a deterministic sheet from bundled artwork, never the user's private photo.
    let sheetContext = CutoutAnimation.context(width: 1024, height: 768)!
    for index in 0..<8 {
        let frame = CharacterFrames.shared.frame(id: "sophia", progress: Double(index) / 8, clip: "dance")!
        sheetContext.draw(frame, in: CGRect(x: index % 4 * 256, y: (1 - index / 4) * 384, width: 256, height: 384))
    }
    let generatedDance = try GeneratedDance.fromSheet(sheetContext.makeImage()!)
    check(generatedDance.frames.count == 8, "A generated sheet becomes eight independent poses")
    check(generatedDance.frames.compactMap(GeneratedDance.decode).allSatisfy(hasClearEdges), "Every extracted pose reserves transparent animation margins")
    do { _ = try GeneratedDance(frames: Array(generatedDance.frames.prefix(7))).validated(); check(false, "Incomplete loops must fail") }
    catch { check(true, "Incomplete saved animations are rejected") }
    do { _ = try GeneratedDance.fromSheet(normalized); check(false, "A lone portrait cannot become a dance sheet") }
    catch { check(true, "A single image is not mistaken for generated motion") }
    let danceFrames = GeneratedDanceFrames()
    let frameZero = danceFrames.frame(id: "fixture", dance: generatedDance, beat: 0)!
    check(digest(frameZero) == digest(danceFrames.frame(id: "fixture", dance: generatedDance, beat: 2)!), "Generated poses loop on the beat")
    check(digest(frameZero) != digest(danceFrames.frame(id: "fixture", dance: generatedDance, beat: 0.5)!), "Generated playback advances through actual limb poses")
    check(danceFrames.frame(id: "fixture", dance: generatedDance, beat: .infinity) != nil, "Nonfinite timing cannot crash generated playback")

    // Continuous clips retain real temporal frames instead of eight-pose sampling.
    let videoFixture = URL(fileURLWithPath: "tools/fixtures/continuous.mp4")
    var importedVideo: Result<GeneratedDance, Error>?
    Task {
        do { importedVideo = .success(try await VideoDance.load(videoFixture)) }
        catch { importedVideo = .failure(error) }
    }
    let videoDeadline = Date().addingTimeInterval(90)
    while importedVideo == nil && Date() < videoDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    check(importedVideo != nil, "Video processing completes without blocking the main run loop")
    let videoDance = try importedVideo!.get()
    check(videoDance.frameRate == 24 && videoDance.frames.count == 48, "A two-second clip retains 48 continuous frames")
    check(videoDance.frames.compactMap(GeneratedDance.decode).allSatisfy(hasClearEdges), "Video background removal keeps transparent canvas margins")
    let videoFrames = GeneratedDanceFrames()
    var videoPoses = Set<Data>()
    for index in 0..<48 {
        videoPoses.insert(digest(videoFrames.frame(id: "video", dance: videoDance, beat: Double(index) / 12 + 0.00001)!))
    }
    check(videoPoses.count > 30, "Continuous playback preserves source motion well beyond eight poses")
    check(digest(videoFrames.frame(id: "video", dance: videoDance, beat: 0)!) == digest(videoFrames.frame(id: "video", dance: videoDance, beat: 4)!), "Video timing loops at the imported clip duration")
    let renamedVideo = try customStore.save(name: "Video persistence test", motion: .bounce, image: GeneratedDance.decode(videoDance.frames[0])!, generatedDance: videoDance)
    check(CustomDancerStore(root: customRoot).find(renamedVideo.id)?.generatedDance?.frameRate == 24, "Video timing and frames survive persistence")
    try customStore.remove(renamedVideo.id)
    for rate in [0.0, -24, Double.infinity, Double.nan, 120] {
        do { _ = try GeneratedDance(frames: videoDance.frames, frameRate: rate).validated(); check(false, "Invalid video timing must fail") }
        catch { check(true, "Video timing is bounded before playback") }
    }
    let avatarScene = try AvatarScene(design: .example)
    let recordedDesign = try JSONDecoder().decode(AvatarDesign.self, from: Data(contentsOf: URL(fileURLWithPath: "tools/fixtures/avatar.json")))
    let recordedScene = try AvatarScene(design: recordedDesign)
    check(!recordedDesign.details.isEmpty && hasClearEdges(recordedScene.frame(motion: .sway, beat: 0.4)!), "A recorded Codex-generated design renders its custom geometry")
    let avatarPortrait = avatarScene.frame(motion: .bounce, beat: 0.5)!
    check(hasClearEdges(avatarPortrait), "3D avatars have transparent, unclipped backgrounds")
    let renderStart = Date()
    for motion in CutoutMotion.allCases {
        var poses = Set<Data>()
        for step in 0..<12 {
            let frame = avatarScene.frame(motion: motion, beat: Double(step) / 3)!
            poses.insert(digest(frame))
            check(hasClearEdges(frame), "\(motion.danceName) fits within the 3D stage")
        }
        check(poses.count >= 8, "\(motion.danceName) articulates the 3D character")
    }
    print(String(format: "3D rendering: %.1f ms/frame for 36 frames.", Date().timeIntervalSince(renderStart) * 1000 / 36))
    check(digest(avatarScene.frame(motion: .bounce, beat: 0, duck: 3)!) != digest(avatarScene.frame(motion: .bounce, beat: 0)!), "3D avatars bend their legs for the lid reaction")

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
    settings.lookId = custom.id
    check(Settings(defaults: defaults).lookId == custom.id, "A custom dancer selection survives preference reload")
    defaults.set("unavailable", forKey: "character")
    check(settings.lookId == "sophia", "Unknown persisted characters recover safely")
    settings.lookId = "manuel"
    settings.squad = 3
    check(settings.dancerIDs == ["manuel", "carla", "nathan"], "Existing trio preferences retain their automatic cast")
    let savedLineup = ["jazz", "sophia", custom.id, "jazz", "manuel"]
    settings.customLineup = savedLineup
    check(Settings(defaults: defaults).dancerIDs == savedLineup, "Mixed lineups preserve order and duplicate dancers after reload")
    let lineupModel = PanelModel()
    lineupModel.refresh(from: settings, loginEnabled: false)
    check(lineupModel.customCompany && lineupModel.squad == 5 && lineupModel.lineup == savedLineup, "The panel restores custom mode, membership, and total count")
    let removedMember = try customStore.save(name: "Temporary member", motion: .bounce, image: normalized)
    settings.customLineup = [removedMember.id, "carla", removedMember.id, "jazz"]
    try customStore.remove(removedMember.id)
    check(settings.dancerIDs == ["carla", "jazz"], "Deleting a custom dancer removes every copy while preserving other members")
    settings.lookId = removedMember.id
    settings.customLineup = [removedMember.id]
    check(settings.dancerIDs == ["sophia"], "A lineup whose entire cast was deleted recovers to one available dancer")
    settings.customLineup = nil
    check(settings.dancerIDs.count == 3, "Clearing custom mode restores the preset count")
    settings.squad = -3
    check(settings.dancerIDs.count == 1, "Invalid old squad counts recover to solo")
    settings.setPosition(0, CGPoint(x: 12, y: 34))
    settings.setPosition(11, CGPoint(x: 56, y: 78))
    settings.setPosition(50, CGPoint(x: 90, y: 12))
    settings.clearPositions()
    check(settings.position(0) == nil && settings.position(11) == nil && settings.position(50) == nil, "Return to Dock clears positions beyond the former eight-slot limit")
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
    let creatorModel = CreatorModel()
    creatorModel.load(invalidFile)
    while creatorModel.busy { settle(0.02) }
    check(creatorModel.error != nil && !creatorModel.canSave, "An invalid import shows an error and cannot be saved")
    try custom.png.write(to: importedFile)
    creatorModel.load(importedFile)
    while creatorModel.busy { settle(0.02) }
    check(creatorModel.image != nil && !creatorModel.canSave && creatorModel.error == nil, "Photo import recovers, but cannot be saved as a finished 3D dancer")
    try creatorModel.acceptAvatar(.example)
    check(creatorModel.canSave && creatorModel.avatar != nil, "A generated 3D character enables saving")
    try creatorModel.acceptLikeness(normalized)
    check(creatorModel.likenessReady && !creatorModel.canSave, "A generated likeness needs dance poses before saving")
    try creatorModel.acceptDance(generatedDance)
    check(creatorModel.isAnimated && creatorModel.canSave && creatorModel.avatar == nil, "Generated dance frames enable saving without primitive geometry")
    check(digest(creatorModel.previewFrame(beat: 0)!) != digest(creatorModel.previewFrame(beat: 0.5)!), "Creator previews generated limb motion")
    try creatorModel.acceptDance(videoDance)
    check(creatorModel.canSave && creatorModel.generatedDance?.isVideo == true, "The creator accepts continuous clips as finished dancers")
    let videoModel = CreatorModel()
    videoModel.loadVideo(videoFixture)
    videoModel.cancelWork()
    settle(0.2)
    check(!videoModel.busy && videoModel.generatedDance == nil, "Cancelling video import prevents stale results from reaching the editor")
    let legacyEditor = CreatorModel(dancer: custom)
    try legacyEditor.acceptLikeness(normalized)
    check(!legacyEditor.canSave, "Upgrading a legacy cutout cannot accidentally save a still likeness as animation")
    creatorModel.name = String(repeating: "a", count: 33)
    check(!creatorModel.canSave, "Overlong names disable saving")
    if PhotoImport.supportsCutout {
        // Exercise Vision on a bundled person composited onto a plain background.
        // Missing system models are allowed, but must keep the original usable.
        let photoContext = CutoutAnimation.context(width: 384, height: 512)!
        photoContext.setFillColor(NSColor.white.cgColor)
        photoContext.fill(CGRect(x: 0, y: 0, width: 384, height: 512))
        photoContext.draw(Companions.portrait("sophia")!, in: CGRect(x: 0, y: 0, width: 384, height: 512))
        let photoData = NSBitmapImageRep(cgImage: photoContext.makeImage()!).representation(using: .png, properties: [:])!
        let photoURL = customRoot.appendingPathComponent("Sophia.png")
        try photoData.write(to: photoURL)
        creatorModel.load(photoURL)
        while creatorModel.busy { settle(0.02) }
        if creatorModel.hasCutout { print("Vision check: import automatically removed the background.") }
        creatorModel.restoreOriginal()
        let beforeCutout = digest(creatorModel.image!)
        creatorModel.removeBackground()
        let deadline = Date().addingTimeInterval(40)
        while creatorModel.busy && Date() < deadline { settle(0.05) }
        if creatorModel.busy { creatorModel.cancelWork(); print("Vision check: system request exceeded 40 seconds; completion cancelled.") }
        else if creatorModel.hasCutout {
            check(digest(creatorModel.image!) != beforeCutout, "Vision changes the photo's background")
            check(hasClearEdges(creatorModel.image!), "Vision output keeps transparent motion margins")
            creatorModel.restoreOriginal()
            check(digest(creatorModel.image!) == beforeCutout && !creatorModel.hasCutout, "Undo background removal restores the original photo")
            print("Vision check: background extraction and undo succeeded.")
        } else {
            check(creatorModel.error != nil && digest(creatorModel.image!) == beforeCutout, "Unavailable extraction retains the original and explains recovery")
            print("Vision check: \(creatorModel.error ?? "No result")")
        }
    }
    creatorModel.load(importedFile)
    creatorModel.cancelWork()
    settle(0.1)
    check(!creatorModel.busy, "Closing a creator invalidates pending import completion")
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
    let mixedLineup = ["jazz", "sophia", custom.id, "bruce", "manuel", "boogie", "carla", "nathan", "jazz", custom.id, "sophia", "bruce"]
    delegate.setLineup(mixedLineup)
    settle()
    check(dancers().count == 12, "Custom company creates more than three or eight native dancers")
    check(dancers().sorted { $0.dancer.index < $1.dancer.index }.map { $0.dancer.characterID } == mixedLineup, "Each native slot uses its explicitly chosen dancer, including duplicates")
    let lineupWindows = Set(dancers().map { ObjectIdentifier($0) })
    delegate.setLook("sophia")
    check(Set(dancers().map { ObjectIdentifier($0) }) == lineupWindows && smokeSettings.dancerIDs == mixedLineup, "Previewing a lineup member keeps the existing dancers and their positions")
    check(smokeSettings.lookId == "sophia", "Lineup members can be selected for preview and dance controls")
    check(dancers().allSatisfy { $0.frame.size == Companions.size(for: $0.dancer.characterID, scale: 5) }, "Mixed people and pixel windows retain their individual aspect ratios")
    check(dancers().filter { !Companions.find($0.dancer.characterID).usesImage }.allSatisfy { $0.dancer.renderer.look.id == $0.dancer.characterID }, "Mixed pixel dancers render the chosen character instead of cycling by index")
    let dockBounds = NSScreen.screens.first!.visibleFrame
    check(dancers().allSatisfy { $0.frame.minX >= dockBounds.minX - 1 && $0.frame.maxX <= dockBounds.maxX + 1 }, "An oversized lineup stays within the desktop width")
    delegate.setFit("raver")
    check(dancers().filter { !Companions.find($0.dancer.characterID).usesImage }.allSatisfy { $0.dancer.renderer.look.id == $0.dancer.characterID }, "Changing wardrobe preserves explicitly selected pixel characters")
    delegate.setHidden(true)
    check(dancers().isEmpty, "Hide applies to the whole custom lineup")
    delegate.setHidden(false)
    check(dancers().count == 12, "Show restores every custom lineup member")
    delegate.setPaused(true)
    settle()
    let mixedPoses = dancers().map { window -> (DancerWindow, Data) in
        let layer = Companions.find(window.dancer.characterID).usesImage ? window.dancer.layer!.sublayers!.first! : window.dancer.layer!
        return (window, digest(layer.contents as! CGImage))
    }
    settle(0.15)
    check(mixedPoses.allSatisfy { window, held in
        let layer = Companions.find(window.dancer.characterID).usesImage ? window.dancer.layer!.sublayers!.first! : window.dancer.layer!
        return digest(layer.contents as! CGImage) == held
    }, "Pause freezes every kind of dancer in a mixed lineup")
    delegate.setPaused(false)
    delegate.setLineup([])
    check(dancers().count == 12, "Removing the last dancer cannot leave an unusable empty lineup")
    delegate.setLineup(mixedLineup + ["unavailable"])
    check(smokeSettings.dancerIDs == mixedLineup, "Unavailable IDs never create unintended extra dancers")
    delegate.setScale(7)
    settle()
    check(dancers().allSatisfy { $0.frame.size == Companions.size(for: $0.dancer.characterID, scale: 7) }, "Resizing a mixed lineup keeps each renderer's proportions")
    delegate.snapToDock()
    check(dancers().allSatisfy { $0.frame.minX >= dockBounds.minX - 1 && $0.frame.maxX <= dockBounds.maxX + 1 }, "Return to Dock fits a large custom lineup after resizing")
    delegate.setLineup(["jazz", custom.id])
    check(dancers().count == 2, "Removing members closes surplus native windows")
    delegate.setSquad(3)
    delegate.setLook("manuel")
    delegate.setScale(5)
    settle()
    check(smokeSettings.customLineup == nil && dancers().count == 3, "Choosing a preset exits custom mode and restores automatic squads")
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
    delegate.setLook(custom.id)
    settle()
    check(dancers().count == 3 && dancers().allSatisfy { Companions.find($0.dancer.characterID).custom }, "Custom trios use the custom cast")
    check(dancers().allSatisfy { $0.dancer.layer?.sublayers?.first?.contents != nil }, "Every custom companion receives an image")
    delegate.setCustomMotion(.bounce)
    check(customStore.find(custom.id)?.motion == .bounce, "Panel motion selection updates the custom dancer")
    delegate.setPaused(true)
    settle()
    let customLayer = dancers().first!.dancer.layer!.sublayers!.first!
    let heldTransform = customLayer.affineTransform()
    settle(0.15)
    check(customLayer.affineTransform() == heldTransform, "Pause freezes native cutout motion")
    previewModel.lookId = custom.id
    previewModel.updatePreview()
    let heldCutoutPreview = digest(previewModel.preview!)
    previewModel.updatePreview()
    check(digest(previewModel.preview!) == heldCutoutPreview, "A paused custom panel preview stays still")
    delegate.setPaused(false)
    settle(0.15)
    check(customLayer.affineTransform() != heldTransform, "Resume restarts cutout motion")
    delegate.openCreator(custom.id)
    settle()
    check(app.windows.contains { $0.title == "Edit dancer" && $0.isVisible }, "Edit opens a standalone creator window")
    app.windows.first { $0.title == "Edit dancer" }?.performClose(nil)
    try customStore.remove(custom.id)
    delegate.setLook(smokeSettings.lookId)
    settle()
    check(smokeSettings.lookId == "sophia" && dancers().first?.dancer.characterID == "sophia", "Deleting the selected custom dancer safely restores Sophia")
    try customStore.remove(secondCustom.id)
    check(CustomDancerStore(root: customRoot).dancers.isEmpty, "Deleted dancers stay deleted after restart")
    let avatarDancer = try customStore.save(name: "3D Avery", motion: .bounce, image: avatarPortrait, avatar: .example)
    let avatarReload = CustomDancerStore(root: customRoot)
    check(avatarReload.find(avatarDancer.id)?.avatar == .example, "3D geometry survives restart without a source photo or AI connection")
    check(Companions.find(avatarDancer.id).detail == "3D avatar", "Generated dancers are labelled as 3D avatars")
    delegate.setLook(avatarDancer.id)
    settle()
    check(dancers().allSatisfy { $0.dancer.layer?.sublayers?.first?.contents != nil }, "3D avatars render in all native dancer windows")
    delegate.setPaused(true)
    settle()
    let native3DLayer = dancers().first!.dancer.layer!.sublayers!.first!
    let held3D = digest(native3DLayer.contents as! CGImage)
    settle(0.15)
    check(digest(native3DLayer.contents as! CGImage) == held3D, "Pause freezes the rendered 3D pose")
    delegate.setPaused(false)
    settle(0.15)
    check(digest(native3DLayer.contents as! CGImage) != held3D, "Resume moves the rendered 3D limbs")
    try customStore.remove(avatarDancer.id)
    let photoDancer = try customStore.save(name: "Photo test", motion: .bounce, image: frameZero, generatedDance: generatedDance)
    let photoReload = CustomDancerStore(root: customRoot)
    check(photoReload.find(photoDancer.id)?.generatedDance?.frames.count == 8, "Generated poses survive restart without AI or the source image")
    check(Companions.find(photoDancer.id).detail == "Photo likeness", "Generated dancers have an accurate label")
    delegate.setLook(photoDancer.id)
    settle()
    let photoLayer = dancers().first!.dancer.layer!.sublayers!.first!
    check(photoLayer.contents != nil && photoLayer.affineTransform() == .identity, "Native windows play generated frames without a rigid-cutout twirl")
    delegate.setPaused(true)
    settle(0.1)
    let heldGenerated = digest(photoLayer.contents as! CGImage)
    settle(0.3)
    check(digest(photoLayer.contents as! CGImage) == heldGenerated, "Pause freezes the generated dancer's pose")
    let photoEditor = CreatorModel(dancer: photoDancer)
    check(photoEditor.canSave && !photoEditor.canAnimate, "Saved generated dancers can be renamed without pretending the original reference is available")
    let photoRenamed = try customStore.save(id: photoDancer.id, name: "Photo renamed", motion: photoDancer.motion, image: frameZero, generatedDance: photoDancer.generatedDance)
    check(photoRenamed.generatedDance?.frames == generatedDance.frames, "Renaming preserves all generated poses")
    try customStore.remove(photoDancer.id)
    check(CustomDancerStore(root: customRoot).find(photoDancer.id) == nil, "Deleting removes the complete saved animation")

    delegate.setLook("boogie")
    settle()
    check(dancers().allSatisfy { !Companions.find($0.dancer.characterID).realistic }, "Classic squads remain available")
    check(dancers().allSatisfy { $0.dancer.layer?.contents != nil }, "Classic sprite rendering still works")
    delegate.setHidden(true)
    smokeDefaults.removePersistentDomain(forName: smokeSuite)
    print("Passed \(checks) checks: continuous video, image generation, dance sheets, legacy 3D avatars, CLI protocol/cancellation, atlas frames, imports/persistence, creator lifecycle, pause/tempo, sensors, and native windows.")

}
