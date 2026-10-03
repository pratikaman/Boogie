import AppKit
import SceneKit

/// A bounded description of geometry. AI returns data, never executable code.
struct AvatarDesign: Codable, Equatable {
    enum Subject: String, Codable, CaseIterable { case human, cat, dog, rabbit, robot }
    enum Hair: String, Codable, CaseIterable { case bald, short, bob, long, curly, bun }
    enum Outfit: String, Codable, CaseIterable { case tshirt, hoodie, jacket, dress }
    enum Joint: String, Codable, CaseIterable {
        case head, torso, hips, leftArm, rightArm, leftForearm, rightForearm, leftLeg, rightLeg, leftShin, rightShin
    }
    enum Shape: String, Codable, CaseIterable { case sphere, box, capsule, cone, torus }
    struct Part: Codable, Equatable {
        let joint: Joint
        let shape: Shape
        let color: String
        let position: [Double]
        let size: [Double]
        let rotation: [Double]
    }
    let version: Int
    let description: String
    let subject: Subject
    let skinColor: String
    let hairColor: String
    let topColor: String
    let bottomColor: String
    let shoeColor: String
    let hair: Hair
    let outfit: Outfit
    let glasses: Bool
    let beard: Bool
    let headScale: Double
    let bodyWidth: Double
    let details: [Part]

    func validated() throws -> AvatarDesign {
        guard version == 1, !description.isEmpty, description.count <= 240,
              [skinColor, hairColor, topColor, bottomColor, shoeColor].allSatisfy(Self.validColor),
              headScale.isFinite, (0.85...1.2).contains(headScale),
              bodyWidth.isFinite, (0.8...1.2).contains(bodyWidth), details.count <= 40 else { throw AvatarError.invalidDesign }
        for part in details {
            guard Self.validColor(part.color), part.position.count == 3, part.size.count == 3, part.rotation.count == 3,
                  part.position.allSatisfy({ $0.isFinite && abs($0) <= 0.65 }),
                  part.size.allSatisfy({ $0.isFinite && (0.005...0.7).contains($0) }),
                  part.rotation.allSatisfy({ $0.isFinite && abs($0) <= 180 }) else { throw AvatarError.invalidDesign }
        }
        return self
    }

    private static func validColor(_ color: String) -> Bool {
        color.count == 7 && color.first == "#" && UInt32(color.dropFirst(), radix: 16) != nil
    }

    static let example = AvatarDesign(version: 1, description: "A little studio dancer in a cream top and blue jeans.",
        subject: .human, skinColor: "#C78B67", hairColor: "#39271E", topColor: "#F1E8D6",
        bottomColor: "#34485D", shoeColor: "#F4EBDB", hair: .long, outfit: .tshirt,
        glasses: false, beard: false, headScale: 1, bodyWidth: 0.95, details: [])
}

enum AvatarError: LocalizedError {
    case invalidDesign, unavailable, notInstalled(String), failed(String), cancelled, timeout
    var errorDescription: String? {
        switch self {
        case .invalidDesign: return "The AI returned an incomplete character. Try generating again."
        case .unavailable: return "3D rendering isn’t available on this Mac."
        case .notInstalled(let provider): return "Install \(provider), sign in from Terminal, then click Refresh."
        case .failed(let message): return message
        case .cancelled: return "Generation cancelled."
        case .timeout: return "Generation took too long. Check your AI sign-in and connection, then try again."
        }
    }
}

extension CutoutMotion {
    var danceName: String {
        switch self { case .bounce: return "Groove"; case .sway: return "Disco"; case .twirl: return "Step & turn" }
    }
}

/// A real 3D character with independent shoulders, elbows, hips, knees and head.
/// The source photo is never used as a billboard or texture in this scene.
final class AvatarScene {
    let scene = SCNScene()
    let camera = SCNNode()
    private let root = SCNNode()
    private var joints: [AvatarDesign.Joint: SCNNode] = [:]
    private var shoes: [SCNNode] = []
    private let design: AvatarDesign
    private let renderer: SCNRenderer
    private var lastKey = ""
    private var lastFrame: CGImage?

    init(design: AvatarDesign) throws {
        self.design = try design.validated()
        guard let device = MTLCreateSystemDefaultDevice() else { throw AvatarError.unavailable }
        renderer = SCNRenderer(device: device, options: nil)
        scene.background.contents = NSColor.clear
        scene.rootNode.addChildNode(root)
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.275
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.7
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 20
        camera.position = SCNVector3(0, 1.11, 5)
        scene.rootNode.addChildNode(camera)
        addLight(type: .ambient, intensity: 180, position: SCNVector3(0, 0, 0), color: .white)
        addLight(type: .omni, intensity: 550, position: SCNVector3(-3, 4, 5), color: NSColor(calibratedRed: 1, green: 0.93, blue: 0.84, alpha: 1))
        addLight(type: .omni, intensity: 220, position: SCNVector3(3, 2, -2), color: NSColor(calibratedRed: 0.8, green: 0.9, blue: 1, alpha: 1))
        build()
        let bounds = root.boundingBox
        let height = max(2.55, (Double(bounds.max.y) + 0.10) / 0.84,
                         (Double(max(abs(bounds.min.x), abs(bounds.max.x))) * 2 + 0.2) / 0.66)
        camera.camera?.orthographicScale = height / 2
        camera.position.y = CGFloat(height * 0.44)
        renderer.scene = scene
        renderer.pointOfView = camera
        renderer.autoenablesDefaultLighting = false
    }

    private func addLight(type: SCNLight.LightType, intensity: CGFloat, position: SCNVector3, color: NSColor) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = type
        node.light?.intensity = intensity
        node.light?.color = color
        node.position = position
        scene.rootNode.addChildNode(node)
    }

    private func joint(_ id: AvatarDesign.Joint, parent: SCNNode, _ x: Float, _ y: Float, _ z: Float = 0) -> SCNNode {
        let node = SCNNode()
        node.name = id.rawValue
        node.position = SCNVector3(x, y, z)
        parent.addChildNode(node)
        joints[id] = node
        return node
    }

    @discardableResult
    private func part(_ shape: AvatarDesign.Shape, _ parent: SCNNode, color: String,
                      size: [Double], position: [Double], rotation: [Double] = [0, 0, 0]) -> SCNNode {
        let geometry: SCNGeometry
        switch shape {
        case .sphere:
            let sphere = SCNSphere(radius: 0.5); sphere.segmentCount = 24; geometry = sphere
        case .box: geometry = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.16)
        case .capsule:
            let capsule = SCNCapsule(capRadius: size[0] / 2, height: max(size[0], size[1])); capsule.radialSegmentCount = 16; geometry = capsule
        case .cone: geometry = SCNCone(topRadius: 0.03, bottomRadius: 0.5, height: 1)
        case .torus: geometry = SCNTorus(ringRadius: 0.4, pipeRadius: 0.07)
        }
        let hex = UInt32(color.dropFirst(), radix: 16) ?? 0x888888
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(calibratedRed: Double((hex >> 16) & 255) / 255,
                                           green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.72
        material.metalness.contents = design.subject == .robot ? 0.25 : 0.0
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.scale = shape == .capsule ? SCNVector3(1, 1, size[2] / size[0]) : SCNVector3(size[0], size[1], size[2])
        node.position = SCNVector3(position[0], position[1], position[2])
        node.eulerAngles = SCNVector3(rotation[0] * .pi / 180, rotation[1] * .pi / 180, rotation[2] * .pi / 180)
        parent.addChildNode(node)
        return node
    }

    private func build() {
        let skin = design.skinColor, hair = design.hairColor, top = design.topColor, bottom = design.bottomColor
        let hips = joint(.hips, parent: root, 0, 0.90)
        part(.box, hips, color: bottom, size: [0.35, 0.20, 0.26], position: [0, 0, 0])
        let torso = joint(.torso, parent: hips, 0, 0.08)
        part(.box, torso, color: top, size: [0.43 * design.bodyWidth, 0.53, 0.29], position: [0, 0.20, 0])
        part(.capsule, torso, color: skin, size: [0.14, 0.17, 0.14], position: [0, 0.51, 0])
        if design.outfit == .hoodie {
            part(.sphere, torso, color: top, size: [0.39, 0.29, 0.28], position: [0, 0.44, -0.08])
            part(.box, torso, color: top, size: [0.23, 0.12, 0.06], position: [0, 0.08, 0.16])
        } else if design.outfit == .jacket {
            part(.box, torso, color: "#EAE2D5", size: [0.12, 0.40, 0.025], position: [0, 0.24, 0.15])
            for side in [-1.0, 1.0] {
                part(.box, torso, color: top, size: [0.075, 0.29, 0.06], position: [side * 0.10, 0.32, 0.16], rotation: [0, 0, side * 15])
            }
        } else if design.outfit == .dress {
            part(.cone, hips, color: top, size: [0.61, 0.48, 0.44], position: [0, -0.12, 0])
        }
        let head = joint(.head, parent: torso, 0, 0.73)
        head.scale = SCNVector3(design.headScale, design.headScale, design.headScale)
        part(design.subject == .robot ? .box : .sphere, head, color: skin, size: [0.44, 0.51, 0.40], position: [0, 0, 0])
        for side in [-1.0, 1.0] {
            part(.sphere, head, color: skin, size: [0.09, 0.13, 0.10], position: [side * 0.225, -0.01, 0])
            part(.sphere, head, color: "#242324", size: [0.044, 0.061, 0.025], position: [side * 0.083, 0.025, 0.194])
            part(.sphere, head, color: "#FFFFFF", size: [0.014, 0.016, 0.012], position: [side * 0.083 - 0.007, 0.035, 0.207])
            if design.glasses {
                part(.torus, head, color: "#302B29", size: [0.15, 0.025, 0.15], position: [side * 0.085, 0.025, 0.219], rotation: [90, 0, 0])
            }
        }
        if design.glasses { part(.box, head, color: "#302B29", size: [0.06, 0.016, 0.015], position: [0, 0.03, 0.226]) }
        part(.sphere, head, color: skin, size: [0.068, 0.086, 0.07], position: [0, -0.05, 0.21])
        part(.box, head, color: "#884C46", size: [0.073, 0.017, 0.019], position: [0, -0.126, 0.183])
        if design.beard {
            part(.sphere, head, color: hair, size: [0.32, 0.17, 0.23], position: [0, -0.18, 0.075])
        }
        if design.subject == .human { addHair(to: head) }
        else if design.subject != .robot {
            for side in [-1.0, 1.0] {
                let rabbit = design.subject == .rabbit, dog = design.subject == .dog
                part(dog ? .capsule : .cone, head, color: hair, size: [rabbit ? 0.11 : 0.16, rabbit ? 0.37 : dog ? 0.29 : 0.20, 0.13],
                     position: [side * 0.16, dog ? 0.06 : rabbit ? 0.33 : 0.24, -0.04], rotation: [0, 0, side * (dog ? 15 : -12)])
            }
            part(.sphere, head, color: skin, size: [0.23, 0.15, 0.16], position: [0, -0.085, 0.19])
            part(.sphere, head, color: "#302B29", size: [0.065, 0.047, 0.045], position: [0, -0.045, 0.279])
        }
        for (side, armID, forearmID, legID, shinID) in [
            (-1.0, AvatarDesign.Joint.leftArm, AvatarDesign.Joint.leftForearm, AvatarDesign.Joint.leftLeg, AvatarDesign.Joint.leftShin),
            (1.0, AvatarDesign.Joint.rightArm, AvatarDesign.Joint.rightForearm, AvatarDesign.Joint.rightLeg, AvatarDesign.Joint.rightShin)
        ] {
            let arm = joint(armID, parent: torso, Float(side * 0.27 * design.bodyWidth), 0.39)
            part(.capsule, arm, color: top, size: [0.15, 0.22, 0.16], position: [0, -0.08, 0])
            part(.capsule, arm, color: design.outfit == .tshirt || design.outfit == .dress ? skin : top,
                 size: [0.12, 0.32, 0.12], position: [0, -0.17, 0])
            let forearm = joint(forearmID, parent: arm, 0, -0.33)
            part(.capsule, forearm, color: design.outfit == .hoodie || design.outfit == .jacket ? top : skin,
                 size: [0.105, 0.28, 0.11], position: [0, -0.13, 0])
            part(.sphere, forearm, color: skin, size: [0.12, 0.14, 0.10], position: [0, -0.30, 0])
            let leg = joint(legID, parent: hips, Float(side * 0.115), -0.02)
            part(.capsule, leg, color: bottom, size: [0.175, 0.41, 0.20], position: [0, -0.19, 0])
            let shin = joint(shinID, parent: leg, 0, -0.41)
            part(.capsule, shin, color: bottom, size: [0.145, 0.39, 0.16], position: [0, -0.18, 0])
            let shoe = part(.box, shin, color: design.shoeColor, size: [0.19, 0.13, 0.30], position: [0, -0.40, 0.055])
            part(.box, shoe, color: "#ECE8DF", size: [0.98, 0.22, 0.98], position: [0, -0.39, 0])
            shoes.append(shoe)
        }
        for detail in design.details {
            guard let parent = joints[detail.joint] else { continue }
            part(detail.shape, parent, color: detail.color, size: detail.size, position: detail.position, rotation: detail.rotation)
        }
    }

    private func addHair(to head: SCNNode) {
        let color = design.hairColor
        guard design.hair != .bald else { return }
        part(.sphere, head, color: color, size: [0.46, 0.23, 0.41], position: [0, 0.20, -0.025])
        switch design.hair {
        case .bob, .long:
            let length = design.hair == .long ? 0.55 : 0.33
            part(.box, head, color: color, size: [0.44, length, 0.22], position: [0, 0.08 - length / 2, -0.12])
            for side in [-1.0, 1.0] {
                part(.capsule, head, color: color, size: [0.13, length, 0.18], position: [side * 0.205, 0.08 - length / 2, 0])
            }
        case .curly:
            for index in 0..<9 {
                let angle = Double(index) * .pi * 2 / 9
                part(.sphere, head, color: color, size: [0.16, 0.17, 0.15], position: [cos(angle) * 0.19, 0.20 + sin(angle) * 0.08, sin(angle) * 0.15])
            }
        case .bun: part(.sphere, head, color: color, size: [0.23, 0.23, 0.23], position: [0, 0.32, -0.10])
        default: break
        }
    }

    func pose(motion: CutoutMotion, beat: Double, duck: Int = 0) {
        let t = (beat.isFinite ? beat : 0) * .pi
        let swing = sin(t), other = sin(t + .pi), sway = sin(t / 2)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        root.position = SCNVector3Zero
        root.eulerAngles = SCNVector3(0, 0.15 + (motion == .twirl ? sway * 0.85 : sway * 0.13), 0)
        joints[.torso]?.eulerAngles = SCNVector3(0, sway * 0.10, sway * 0.055)
        joints[.head]?.eulerAngles = SCNVector3(0.035 * swing, -sway * 0.14, -sway * 0.08)
        for (side, arm, forearm, leg, shin, phase) in [
            (-1.0, AvatarDesign.Joint.leftArm, AvatarDesign.Joint.leftForearm, AvatarDesign.Joint.leftLeg, AvatarDesign.Joint.leftShin, swing),
            (1.0, AvatarDesign.Joint.rightArm, AvatarDesign.Joint.rightForearm, AvatarDesign.Joint.rightLeg, AvatarDesign.Joint.rightShin, other)
        ] {
            let raised = motion == .sway && side > 0
            joints[arm]?.eulerAngles = SCNVector3(phase * 0.40 - 0.10, 0,
                side * (raised ? 1.80 + 0.55 * swing : 0.22 + 0.25 * abs(phase)))
            joints[forearm]?.eulerAngles = SCNVector3(-0.70 - 0.45 * phase, 0, raised ? 0.15 : side * 0.12)
            joints[leg]?.eulerAngles = SCNVector3(phase * (motion == .twirl ? 0.45 : 0.25), 0, side * 0.035)
            joints[shin]?.eulerAngles = SCNVector3(max(0, -phase) * 0.55, 0, 0)
            if duck > 0 {
                let bend = Double(min(3, duck)) * 0.22
                joints[leg]?.eulerAngles.x = CGFloat(-bend)
                joints[shin]?.eulerAngles.x = CGFloat(bend * 2)
                joints[arm]?.eulerAngles = SCNVector3(-0.4, 0, side * 0.4)
            }
        }
        let lowest = shoes.map { $0.convertPosition(SCNVector3(0, -0.6, 0), to: root).y }.min() ?? 0
        root.position.y = -lowest + CGFloat(duck > 0 ? 0 : abs(swing) * 0.035)
        SCNTransaction.commit()
    }

    func frame(motion: CutoutMotion, beat: Double, duck: Int = 0) -> CGImage? {
        let step = Int((max(0, beat.isFinite ? beat : 0).truncatingRemainder(dividingBy: 4)) * 24)
        let key = "\(motion.rawValue)-\(step)-\(duck)"
        if key == lastKey { return lastFrame }
        pose(motion: motion, beat: Double(step) / 24, duck: duck)
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 384, height: 512), antialiasingMode: .multisampling4X)
        let result = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        lastKey = key
        lastFrame = result
        return result
    }
}

final class AvatarFrames {
    static let shared = AvatarFrames()
    private var scenes: [String: AvatarScene] = [:]
    func invalidate(_ id: String) { scenes[id] = nil }
    func frame(id: String, design: AvatarDesign, motion: CutoutMotion, beat: Double, duck: Int = 0) -> CGImage? {
        if scenes[id] == nil {
            if scenes.count >= 6 { scenes.removeAll() }
            scenes[id] = try? AvatarScene(design: design)
        }
        return scenes[id]?.frame(motion: motion, beat: beat, duck: duck)
    }
}
