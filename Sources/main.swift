import AppKit
import SwiftUI

let app = NSApplication.shared

// `Boogie --render-panel out.png` renders the control panel offscreen with
// sample data, for README screenshots and layout checks.
if let i = CommandLine.arguments.firstIndex(of: "--render-panel"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        let model = PanelModel.sample()
        let renderer = ImageRenderer(content: PanelView(model: model))
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
