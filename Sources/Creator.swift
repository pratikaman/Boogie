import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CreatorModel: ObservableObject {
    @Published var name = ""
    @Published var motion = CutoutMotion.bounce
    @Published var image: CGImage?
    @Published var busy = false
    @Published var error: String?
    @Published var hasCutout = false
    @Published var avatar: AvatarDesign?
    @Published var stage = ""
    let provider = AvatarProvider.codex
    @Published var generatedDance: GeneratedDance?
    @Published var likenessReady = false
    @Published var providerInstalled = false
    let editingID: String?
    private var original: CGImage?
    private var photoForAI: CGImage?
    private var operation = UUID()
    private var generation: AvatarGeneration?
    private var videoImport: Task<Void, Never>?
    private var avatarScene: AvatarScene?
    private var likenessImage: CGImage?
    private var previewID = UUID().uuidString
    private let legacyCutout: Bool
    private var photoChanged = false

    init(dancer: CustomDancer? = nil) {
        editingID = dancer?.id
        legacyCutout = dancer != nil && dancer?.isAnimated == false
        if let dancer {
            name = dancer.name
            motion = dancer.motion
            image = CustomDancerStore.shared.image(dancer.id)
            avatar = dancer.avatar
            generatedDance = dancer.generatedDance
            if let avatar { avatarScene = try? AvatarScene(design: avatar) }
            else if generatedDance == nil { original = image; photoForAI = image }
        }
        refreshProvider()
    }

    var canSave: Bool {
        image != nil && (avatar != nil || generatedDance != nil || (legacyCutout && !photoChanged)) && !busy
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 32
    }
    var canGenerate: Bool { photoForAI != nil && providerInstalled && !busy }
    var canAnimate: Bool { likenessImage != nil && providerInstalled && !busy }
    var isAnimated: Bool { avatar != nil || generatedDance != nil }
    var canRemoveBackground: Bool { original != nil && !hasCutout && PhotoImport.supportsCutout }
    var hasPhoto: Bool { photoForAI != nil }

    func refreshProvider() { providerInstalled = provider.executable() != nil }

    func load(_ url: URL) {
        stage = "Separating the subject from the background…"
        work {
            let source = try PhotoImport.load(url)
            let subject = PhotoImport.supportsCutout ? (try? PhotoImport.removeBackground(source)) : nil
            return (source, try PhotoImport.normalize(subject ?? source), subject)
        } complete: { source, normalized, subject in
            self.original = source
            self.photoForAI = source
            self.photoChanged = true
            self.image = normalized
            self.hasCutout = subject != nil
            self.avatar = nil
            self.avatarScene = nil
            self.clearLikeness()
            self.stage = "Photo ready. Generate a realistic likeness, then review it before animating."
            if self.name.isEmpty { self.name = String(url.deletingPathExtension().lastPathComponent.prefix(32)) }
        }
    }

    func removeBackground() {
        guard let original else { return }
        stage = "Removing the background…"
        work {
            let cutout = try PhotoImport.removeBackground(original)
            return (original, try PhotoImport.normalize(cutout), cutout)
        } complete: { _, normalized, cutout in
            self.image = normalized
            self.photoForAI = cutout
            self.hasCutout = true
            self.avatar = nil
            self.avatarScene = nil
            self.clearLikeness()
            self.stage = "Photo ready. Generate a realistic likeness, then review it before animating."
        }
    }

    func restoreOriginal() {
        guard let original else { return }
        do {
            image = try PhotoImport.normalize(original)
            hasCutout = false
            photoForAI = original
            avatar = nil
            avatarScene = nil
            clearLikeness()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func cancelWork() {
        operation = UUID()
        videoImport?.cancel()
        videoImport = nil
        generation?.cancel()
        generation = nil
        busy = false
        stage = "Generation cancelled. You can try again."
    }

    func loadVideo(_ url: URL) {
        guard !busy else { return }
        let token = UUID()
        operation = token
        busy = true
        error = nil
        stage = "Preparing continuous dance frames…"
        videoImport = Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<GeneratedDance, Error>
            do {
                let dance = try await VideoDance.load(url) { progress in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.operation == token else { return }
                        self.stage = "Preparing continuous dance frames… \(Int(progress * 100))%"
                    }
                }
                result = .success(dance)
            } catch { result = .failure(error) }
            await MainActor.run { [weak self] in
                guard let self, self.operation == token else { return }
                self.busy = false
                self.videoImport = nil
                do {
                    try self.acceptDance(result.get())
                    if self.name.isEmpty { self.name = String(url.deletingPathExtension().lastPathComponent.prefix(32)) }
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    func generateAvatar() {
        guard canGenerate, let photoForAI else { return }
        startGeneration(image: photoForAI, stage: .portrait)
    }

    func animateLikeness() {
        guard canAnimate, let likenessImage else { return }
        startGeneration(image: likenessImage, stage: .dance)
    }

    private func startGeneration(image: CGImage, stage: LikenessAI.Stage) {
        let token = UUID()
        operation = token
        busy = true
        error = nil
        self.stage = stage == .portrait ? "Codex is generating your likeness. This may take a few minutes…" : "Codex is drawing eight dance poses. This may take a few minutes…"
        let job = AvatarGeneration(timeout: 600)
        generation = job
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () -> (CGImage, GeneratedDance?) in
                let output = try LikenessAI.generate(image: image, stage: stage, job: job)
                if stage == .dance { return (output, try GeneratedDance.fromSheet(output)) }
                let cutout = PhotoImport.supportsCutout ? (try? PhotoImport.removeBackground(output)) : nil
                return (cutout ?? output, nil)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operation == token else { return }
                self.generation = nil
                self.busy = false
                do {
                    let (output, dance) = try result.get()
                    if let dance { try self.acceptDance(dance) }
                    else { try self.acceptLikeness(output) }
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func clearLikeness() {
        likenessImage = nil
        likenessReady = false
        generatedDance = nil
        GeneratedDanceFrames.shared.invalidate(previewID)
    }

    func acceptLikeness(_ portrait: CGImage) throws {
        let normalized = try PhotoImport.normalize(portrait)
        clearLikeness()
        photoChanged = true
        likenessImage = portrait
        likenessReady = true
        avatar = nil
        avatarScene = nil
        image = normalized
        stage = "Check the face and outfit. Happy with the likeness? Animate it next."
    }

    func acceptDance(_ dance: GeneratedDance) throws {
        _ = try dance.validated()
        guard let thumbnail = GeneratedDance.decode(dance.frames[0]) else { throw LikenessError.invalidSheet }
        GeneratedDanceFrames.shared.invalidate(previewID)
        generatedDance = dance
        avatar = nil
        avatarScene = nil
        image = thumbnail
        stage = dance.isVideo ? "Continuous dance imported at 24 fps. Check the loop before saving." : "Eight-pose preview ready. For smooth motion, import a continuous dance video."
    }

    func acceptAvatar(_ design: AvatarDesign) throws {
        let scene = try AvatarScene(design: design)
        guard let thumbnail = scene.frame(motion: motion, beat: 0.4) else { throw AvatarError.unavailable }
        clearLikeness()
        avatarScene = scene
        avatar = design
        image = thumbnail
        stage = "Your 3D avatar is ready. Preview a dance, then add it to your Dock."
    }

    func previewFrame(beat: Double) -> CGImage? {
        if let generatedDance { return GeneratedDanceFrames.shared.frame(id: previewID, dance: generatedDance, beat: beat) }
        if let avatarScene { return avatarScene.frame(motion: motion, beat: beat) }
        return image
    }

    private func work(_ task: @escaping () throws -> (CGImage, CGImage, CGImage?), complete: @escaping (CGImage, CGImage, CGImage?) -> Void) {
        let token = UUID()
        operation = token
        busy = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try task() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operation == token else { return }
                self.busy = false
                switch result {
                case .success(let images): complete(images.0, images.1, images.2)
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
}

/// A separate window keeps the creator open while the menu-bar popover closes.
final class CreatorWindowController: NSWindowController, NSWindowDelegate {
    let model: CreatorModel

    init(dancer: CustomDancer?, saved: @escaping (String) -> Void, deleted: @escaping (String) -> Void) {
        model = CreatorModel(dancer: dancer)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 740),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = dancer == nil ? "Create a dancer" : "Edit dancer"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.delegate = self
        window.contentView = NSHostingView(rootView: CreatorView(model: model, chooseImage: { [weak self] in
            self?.chooseImage()
        }, save: { [weak self] in
            guard let self, let image = self.model.image, self.model.canSave else { return }
            do {
                let dancer = try CustomDancerStore.shared.save(id: self.model.editingID, name: self.model.name,
                                                              motion: self.model.motion, image: image, avatar: self.model.avatar, generatedDance: self.model.generatedDance)
                saved(dancer.id)
                self.close()
            } catch { self.model.error = error.localizedDescription }
        }, cancel: { [weak self] in self?.close() }, chooseVideo: { [weak self] in self?.chooseVideo() }, locateAI: { [weak self] in self?.locateAI() }, delete: { [weak self] in
            guard let self, let id = self.model.editingID else { return }
            do {
                try CustomDancerStore.shared.remove(id)
                deleted(id)
                self.close()
            } catch { self.model.error = error.localizedDescription }
        }))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    func windowWillClose(_ notification: Notification) { model.cancelWork() }

    private func chooseImage() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a clear photo of one person. Keep their face and outfit visible."
        panel.prompt = "Use image"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.model.load(url)
        }
    }

    private func chooseVideo() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a 1–8 second looping dance video. Keep one full-body person and a fixed camera; Boogie removes the background locally."
        panel.prompt = "Use dance video"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.model.loadVideo(url)
        }
    }

    private func locateAI() {
        guard let window else { return }
        let provider = model.provider
        let panel = NSOpenPanel()
        panel.message = "Locate the \(provider.rawValue) command-line executable."
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard FileManager.default.isExecutableFile(atPath: url.path), url.lastPathComponent == provider.rawValue else {
                self?.model.error = "Choose the executable named ‘\(provider.rawValue)’."
                return
            }
            UserDefaults.standard.set(url.path, forKey: "aiExecutable.\(provider.rawValue)")
            self?.model.refreshProvider()
        }
    }
}

struct CreatorView: View {
    @ObservedObject var model: CreatorModel
    var chooseImage: () -> Void
    var save: () -> Void
    var cancel: () -> Void
    var chooseVideo: () -> Void = {}
    var locateAI: () -> Void = {}
    var delete: () -> Void
    var staticRender = false
    @State private var confirmDelete = false
    @State private var targeted = false
    @State private var previewPaused = false
    @State private var start = Date()
    @State private var heldBeat = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.editingID == nil ? "Your face. Your style. Your dancer." : "Make it your own.")
                    .font(.system(size: 27, design: .serif)).tracking(-0.5)
                Text("Generate a realistic likeness, review it, then bring it to life.")
                    .font(.system(size: 12)).foregroundColor(Studio.secondary)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 10) {
                    preview
                    Button(previewPaused ? "Play preview" : "Pause preview") {
                        if previewPaused { start = Date().addingTimeInterval(-heldBeat / 2) }
                        else { heldBeat = Date().timeIntervalSince(start) * 2 }
                        previewPaused.toggle()
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Studio.secondary)
                        .disabled(!model.isAnimated)
                    Text(model.isAnimated ? "DANCE PREVIEW" : (model.likenessReady ? "REVIEW YOUR LIKENESS" : "REFERENCE PHOTO"))
                        .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundColor(Studio.secondary)
                    if let avatar = model.avatar {
                        Text(avatar.description).font(.system(size: 11)).foregroundColor(Studio.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(width: 248)
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("01  Choose an image")
                        Button(action: chooseImage) {
                            Label(model.image == nil ? "Choose image…" : "Replace image…", systemImage: "photo")
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                        }.disabled(model.busy)
                        Text("One clear face and outfit. A full-body photo leaves less for AI to invent.")
                            .font(.system(size: 10)).foregroundColor(Studio.secondary).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("02  Create with your AI")
                        Text("Codex · image generation").font(.system(size: 12, weight: .medium))
                        HStack {
                            Text(model.providerInstalled ? "CLI found · uses your existing sign-in" : "CLI not found on this Mac")
                                .font(.system(size: 10)).foregroundColor(Studio.secondary)
                            Spacer()
                            Button("Refresh") { model.refreshProvider() }.disabled(model.busy)
                        }
                        if !model.providerInstalled {
                            HStack {
                                Button("Locate CLI…", action: locateAI)
                                Text("Sign in first: \(model.provider.loginCommand)").textSelection(.enabled)
                            }.font(.system(size: 10))
                        }
                        Button(model.likenessReady || model.isAnimated ? "Regenerate likeness" : "Generate likeness") { model.generateAvatar() }
                            .buttonStyle(.borderedProminent).disabled(!model.canGenerate)
                        if model.likenessReady {
                            Button(model.generatedDance == nil ? "Make 8-pose preview" : "Regenerate 8 poses") { model.animateLikeness() }
                                .buttonStyle(.borderedProminent).disabled(!model.canAnimate)
                        }
                        if model.isAnimated && !model.hasPhoto {
                            Text("Choose a new photo to regenerate this dancer.").font(.system(size: 10)).foregroundColor(Studio.secondary)
                        }
                        Button("Import smooth dance video…", action: chooseVideo).disabled(model.busy)
                        Text("For smooth motion, use a 1–8 second video. The Codex option generates eight still poses.")
                            .font(.system(size: 10)).foregroundColor(Studio.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("Image generation uses your Codex account and sends its reference to OpenAI. Video import stays on this Mac.")
                            .font(.system(size: 10)).foregroundColor(Studio.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("03  Name & dance")
                        TextField("Your dancer’s name", text: $model.name).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Dancer name")
                        if model.name.count > 32 {
                            Text("Keep it to 32 characters.").font(.system(size: 10)).foregroundColor(Studio.accent)
                        }
                        if model.avatar != nil || (model.editingID != nil && !model.isAnimated && !model.likenessReady) {
                            Picker("Motion", selection: $model.motion) {
                                ForEach(CutoutMotion.allCases) { Text(model.avatar == nil ? $0.name : $0.danceName).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                        } else {
                            Text(model.generatedDance?.isVideo == true ? "Video dance · 24 fps at Groove pace" : "Photo groove · 8 poses").font(.system(size: 11))
                        }
                        Text("Realistic rendered poses. Preview both likeness and movement before saving.")
                            .font(.system(size: 10)).foregroundColor(Studio.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.stage).font(.system(size: 11))
                    Spacer()
                    Button("Stop") { model.cancelWork() }
                }
            } else if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundColor(Studio.accent)
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel("Error: \(error)")
            } else {
                Text(model.stage.isEmpty ? "Create once with AI. Your saved dancer then works offline." : model.stage)
                    .font(.system(size: 11)).foregroundColor(Studio.secondary)
            }
            Spacer(minLength: 0)
            Rectangle().fill(Studio.line).frame(height: 1)
            HStack {
                if model.editingID != nil {
                    Button("Delete dancer…", role: .destructive) { confirmDelete = true }.disabled(model.busy)
                }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(model.editingID == nil ? "Add to my dancers" : "Save changes", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(!model.canSave)
            }
        }
        .padding(26).frame(width: 720, height: 740)
        .foregroundColor(Studio.ink).background(Studio.paper).tint(Studio.accent).preferredColorScheme(.light)
        .alert("Delete this dancer?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: { Text("The saved dancer will be removed from Boogie. Your original image stays where it is.") }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Studio.surface)
            UnevenArch().fill(Color(hex: 0xE3D9CA)).frame(width: 180, height: 240).offset(x: 16, y: 15)
            if let image = model.image {
                if staticRender {
                    previewImage(image, beat: 0.6)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 24, paused: previewPaused || !model.isAnimated)) { context in
                        previewImage(image, beat: previewPaused ? heldBeat : context.date.timeIntervalSince(start) * 2)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.rectangle.badge.plus").font(.system(size: 32, weight: .light))
                    Text("Start with your photo.\nKeep what makes it you.").font(.system(size: 16, design: .serif)).multilineTextAlignment(.center)
                    Button("Choose an image", action: chooseImage)
                    Text("or drop one here").font(.system(size: 10))
                }.foregroundColor(Studio.secondary)
            }
        }
        .frame(width: 248, height: 306).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(targeted ? Studio.accent : .clear, lineWidth: 2))
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.busy, let url = urls.first, url.isFileURL else { return false }
            if ["mov", "mp4"].contains(url.pathExtension.lowercased()) { model.loadVideo(url) }
            else { model.load(url) }
            return true
        } isTargeted: { targeted = $0 }
    }

    private func previewImage(_ image: CGImage, beat: Double) -> some View {
        Image(decorative: model.previewFrame(beat: beat) ?? image, scale: 1)
            .resizable().interpolation(.high).scaledToFit().frame(width: 224, height: 299)
            .accessibilityLabel("Live \(model.motion.name.lowercased()) preview")
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundColor(Studio.secondary)
    }
}
