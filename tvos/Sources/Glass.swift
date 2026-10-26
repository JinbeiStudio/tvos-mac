import AppKit
import SwiftUI

/// tvOS 26's Liquid Glass light: no frame, only a sheen across the top and a glint where light catches the top edge.
struct GlassEdge<S: Shape>: View {
    let shape: S
    var body: some View {
        ZStack {
            shape.fill(LinearGradient(
                gradient: Gradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.02), Color.clear]),
                startPoint: .top, endPoint: .center
            ))
            shape.stroke(LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.white.opacity(0.45), location: 0),
                    .init(color: Color.white.opacity(0), location: 0.18),
                    .init(color: Color.white.opacity(0), location: 0.85),
                    .init(color: Color.white.opacity(0.15), location: 1),
                ]),
                startPoint: .top, endPoint: .bottom
            ), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The home's profile picture, beside the time: profile.jpg (or .png, .jpeg, .webp, .heic) put beside the sources at build time.
enum ProfilePicture {
    static let image: NSImage? = {
        for ext in ["jpg", "jpeg", "png", "webp", "heic"] {
            if let path = Bundle.main.path(forResource: "profile", ofType: ext) { return NSImage(contentsOfFile: path) }
        }
        return nil
    }()
}
