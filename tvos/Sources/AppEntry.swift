import AppKit
import SwiftUI

/// An installed app; its icon and tint are read once, when first drawn.
final class AppEntry: Identifiable, Equatable {
    let url: URL
    let name: String
    var id: String { url.path }

    init(url: URL) {
        self.url = url
        // "NVIDIA GeForce NOW" is too long for a tile's label.
        self.name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: "NVIDIA ", with: "")
    }

    lazy var icon: NSImage = {
        // A symlinked app such as Safari would otherwise carry the shortcut arrow.
        let image = NSWorkspace.shared.icon(forFile: url.resolvingSymlinksInPath().path)
        image.size = NSSize(width: 512, height: 512)
        return image
    }()

    /// The icon's average colour, which the tile takes as its background.
    lazy var tint: Color = {
        guard let cg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .gray }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .gray }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = max(Double(px[3]) / 255, 0.05)
        let r = min(Double(px[0]) / 255 / alpha, 1)
        let g = min(Double(px[1]) / 255 / alpha, 1)
        let b = min(Double(px[2]) / 255 / alpha, 1)
        // Darkened, so a bright icon reads on it.
        return Color(red: r * 0.7, green: g * 0.7, blue: b * 0.7)
    }()

    /// How light the icon's background is, 0 to 1; set once `base` has been read.
    private(set) var luminance = 1.0

    /// The colour a little inside the icon's left edge, which is the icon's own background.
    lazy var base: Color = {
        guard let cg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return tint }
        let side = 64
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return tint }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        // Icons keep a margin of about a tenth; just inside its top edge there is only background, whatever the glyph.
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for x in [19, 29, 35, 45] {
            let at = (9 * side + x) * 4
            let alpha = Double(px[at + 3]) / 255
            guard alpha > 0.6 else { continue }
            r += Double(px[at]) / 255 / alpha
            g += Double(px[at + 1]) / 255 / alpha
            b += Double(px[at + 2]) / 255 / alpha
            n += 1
        }
        guard n > 0 else { return tint }
        luminance = 0.2126 * r / n + 0.7152 * g / n + 0.0722 * b / n
        return Color(red: min(r / n, 1), green: min(g / n, 1), blue: min(b / n, 1))
    }()

    /// Brand logos (Simple Icons) matched by app name; those apps get their glyph on the brand colour, as on tvOS.
    private static let brands: [(match: String, slug: String)] = [
        ("youtube music", "youtubemusic"), ("youtube", "youtube"), ("safari", "safari"), ("app store", "appstore"),
        ("podcasts", "applepodcasts"), ("music", "applemusic"), ("spotify", "spotify"), ("vlc", "vlcmediaplayer"),
        ("plex", "plex"), ("kodi", "kodi"), ("jellyfin", "jellyfin"), ("netflix", "netflix"), ("hbo", "hbo"),
        ("twitch", "twitch"), ("discord", "discord"), ("firefox", "firefox"), ("chrome", "googlechrome"),
        ("steam", "steam"), ("crunchyroll", "crunchyroll"), ("geforce", "nvidia"),
    ]

    /// The brand's colour and its logo drawn in white, when this app has one.
    lazy var brand: (color: Color, glyph: NSImage)? = {
        let lower = name.lowercased()
        var slug: String?
        if lower == "tv" { slug = "appletv" }
        else { slug = AppEntry.brands.first { lower.contains($0.match) }?.slug }
        guard let found = slug,
              let path = Bundle.main.path(forResource: found, ofType: "svg", inDirectory: "icons"),
              let text = try? String(contentsOfFile: path, encoding: .utf8),
              let range = text.range(of: "fill=\"#[0-9A-Fa-f]{6}\"", options: .regularExpression)
        else { return nil }
        let hex = String(text[range]).dropFirst(7).dropLast(1)
        guard let value = UInt32(hex, radix: 16) else { return nil }
        let white = text.replacingCharacters(in: range, with: "fill=\"#FFFFFF\"")
        guard let glyph = NSImage(data: Data(white.utf8)) else { return nil }
        let color = Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
        return (color, glyph)
    }()

    static func == (a: AppEntry, b: AppEntry) -> Bool { a.id == b.id }
}
