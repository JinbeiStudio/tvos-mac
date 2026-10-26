import AppKit
import SwiftUI

/// The row of apps: which are on it, which is focused in the overlay, and the editor that picks them.
final class HomeModel: ObservableObject {
    static let shared = HomeModel()

    /// Every app on the Mac, for the editor.
    @Published var all: [AppEntry] = []
    /// The row of apps, in order.
    @Published var shelf: [AppEntry] = []
    @Published var focus = 0
    @Published var editRow = 0

    private let key = "shelf"
    /// The row the first time, by name, where installed.
    private let favourites = [
        "AIOStreams", "YouTube", "NVIDIA GeForce NOW", "GeForce NOW", "Infuse", "Safari", "Music", "Photos",
        "Plex", "Spotify", "System Settings",
    ]

    private init() {
        all = HomeModel.scan()
        if let saved = UserDefaults.standard.stringArray(forKey: key) {
            shelf = saved.compactMap { path in all.first { $0.id == path } }
        } else {
            shelf = favourites.compactMap { name in all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
            if shelf.isEmpty { shelf = Array(all.prefix(8)) }
        }
    }

    static func scan() -> [AppEntry] {
        let roots = [
            "/Applications", "/System/Applications", "/Applications/Utilities",
            "/System/Applications/Utilities", NSHomeDirectory() + "/Applications",
        ]
        var found: [String: AppEntry] = [:]
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") && item != "tvOS.app" {
                let entry = AppEntry(url: URL(fileURLWithPath: root + "/" + item))
                found[entry.id] = entry
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func save() { UserDefaults.standard.set(shelf.map { $0.id }, forKey: key) }

    func launch(_ entry: AppEntry) {
        AppSwitcher.shared.close()
        if entry.url.path == Launcher.aiostreams.path { return Launcher.openAIOStreams() }
        if entry.url.path == Launcher.youtube.path { return Launcher.openYouTube() }
        Launcher.open(entry.url)
    }

    func toggle(_ entry: AppEntry) {
        if let at = shelf.firstIndex(of: entry) { shelf.remove(at: at) } else { shelf.append(entry) }
        focus = min(focus, max(shelf.count - 1, 0))
        save()
    }

    /// Moves an app one place along the row; apps not on it stay put.
    func move(_ entry: AppEntry, by step: Int) {
        guard let at = shelf.firstIndex(of: entry) else { return }
        let to = at + step
        guard to >= 0, to < shelf.count else { return }
        shelf.swapAt(at, to)
        focus = to
        save()
    }

    /// Keys in the editor's window (the remote's arrows and OK arrive as keys); true when used.
    func handleEditor(_ event: NSEvent) -> Bool {
        guard !all.isEmpty else { return false }
        switch event.keyCode {
        case 126: editRow = max(0, editRow - 1)
        case 125: editRow = min(all.count - 1, editRow + 1)
        case 36, 76, 49: toggle(all[editRow])
        case 123: move(all[editRow], by: -1)
        case 124: move(all[editRow], by: 1)
        case 53, 51: NSApp.keyWindow?.close()
        default: return false
        }
        return true
    }
}

/// A frosted pane, as the dock is drawn.
struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // The lightest blur, so the picture behind shows through like glass rather than a dark panel.
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The apps, in a frosted pane like tvOS's; the focused one lifts and its name shows under it.
struct Dock: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        ZStack {
            Glass()
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40) {
                        ForEach(Array(model.shelf.enumerated()), id: \.element.id) { index, entry in
                            Tile(entry: entry, focused: index == model.focus)
                                .id(entry.id)
                                .onHover { inside in if inside { model.focus = index } }
                                .onTapGesture { model.launch(entry) }
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, 36)
                    .padding(.bottom, 14)
                }
                .onChange(of: model.focus) { index in
                    guard index < model.shelf.count else { return }
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(model.shelf[index].id, anchor: .center) }
                }
            }
        }
        .frame(height: 224)
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .overlay(GlassEdge(shape: RoundedRectangle(cornerRadius: 46, style: .continuous)))
        .shadow(color: Color.black.opacity(0.25), radius: 30, y: 12)
        .padding(.horizontal, 110)
    }
}

struct Tile: View {
    let entry: AppEntry
    let focused: Bool

    /// A dark icon is drawn larger, so its glyph is as big on black as the logos are on their colours.
    private var size: CGFloat { entry.luminance < 0.12 ? 232 : 156 }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let brand = entry.brand {
                    // The logo whole and white on the brand's colour.
                    LinearGradient(
                        gradient: Gradient(colors: [brand.color, brand.color.opacity(0.78)]),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(nsImage: brand.glyph)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 84)
                } else {
                    // The whole icon, on its own background colour so its edge disappears, as the logos sit on theirs.
                    entry.base
                    Image(nsImage: entry.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .mask(RadialGradient(gradient: Gradient(colors: [Color.black, Color.clear]), center: .center, startRadius: size * 0.32, endRadius: size * 0.40))
                }
            }
            .frame(width: 200, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(focused ? 0.2 : 0.05), Color.clear]), startPoint: .top, endPoint: .center))
            )
            .scaleEffect(focused ? 1.18 : 1)
            .offset(y: focused ? -8 : 0)
            .shadow(color: .black.opacity(focused ? 0.55 : 0.2), radius: focused ? 26 : 6, y: focused ? 18 : 4)
            Text(entry.name)
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white.opacity(focused ? 0.95 : 0))
                .lineLimit(1)
                .frame(width: 200)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: focused)
    }
}

/// Every app on the Mac, with the ones on the row marked and numbered.
struct Editor: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("Edit apps")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                Text("OK adds or removes · Left and Right move it along the row · Back closes")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.5))
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(model.all.enumerated()), id: \.element.id) { index, entry in
                                EditorRow(entry: entry, place: model.shelf.firstIndex(of: entry), selected: index == model.editRow)
                                    .id(entry.id)
                                    .onTapGesture { model.editRow = index; model.toggle(entry) }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: model.editRow) { row in
                        guard row < model.all.count else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(model.all[row].id, anchor: .center) }
                    }
                }
            }
            .padding(40)
        }
    }
}

struct EditorRow: View {
    let entry: AppEntry
    let place: Int?
    let selected: Bool

    var body: some View {
        HStack(spacing: 18) {
            Image(nsImage: entry.icon).resizable().frame(width: 52, height: 52)
            Text(entry.name)
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text(place.map { "\($0 + 1)" } ?? "")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color(red: 0.3, green: 0.75, blue: 1))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(selected ? 0.18 : 0.05)))
        .scaleEffect(selected ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}
