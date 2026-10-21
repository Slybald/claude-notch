import AppKit
import SwiftUI

// Usage : swift run Maquettes <dossier de sortie>  (par défaut : le dossier courant)
@MainActor func render<V: View>(_ view: V, name: String, in folder: URL, scale: CGFloat = 2) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("échec du rendu : \(name)\n".utf8))
        exit(1)
    }
    let url = folder.appendingPathComponent(name)
    do { try png.write(to: url) } catch {
        FileHandle.standardError.write(Data("écriture impossible : \(url.path)\n".utf8))
        exit(1)
    }
    print("écrit : \(url.path) (\(image.width)×\(image.height))")
}

let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
MainActor.assumeIsolated {
    render(commandeBoard(), name: "commande.png", in: folder)
    render(agendaBoard(), name: "agenda.png", in: folder)
    render(approbationBoard(), name: "approbation.png", in: folder)
}
