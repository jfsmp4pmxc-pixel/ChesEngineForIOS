import SwiftUI
import UIKit

// MARK: - Colours stored as hex strings

extension Color {
    /// "#RRGGBB" or "RRGGBB".
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ x: CGFloat) -> Int { return Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

/// Keys and defaults for the look of the board.
enum Theme {
    static let lightSquareKey = "boardLightSquare"
    static let darkSquareKey = "boardDarkSquare"
    static let userArrowKey = "userArrowColor"
    static let bestArrowKey = "bestArrowColor"
    /// Bumped whenever a custom image is added or removed, so views redraw.
    static let assetsVersionKey = "customAssetsVersion"

    static let defaultLight = "#EDEDD1"
    static let defaultDark = "#75964F"
    static let defaultUserArrow = "#26A64D"
    static let defaultBestArrow = "#FF9500"

    /// A colour binding backed by a hex string (for `ColorPicker`).
    static func binding(_ hex: Binding<String>, fallback: String) -> Binding<Color> {
        return Binding<Color>(
            get: { Color(hex: hex.wrappedValue) ?? Color(hex: fallback) ?? .gray },
            set: { hex.wrappedValue = $0.hexString }
        )
    }
}

// MARK: - Custom images

/// Images the player imported to replace the built-in pieces and move badges. They live
/// in Documents/Custom as PNG files named like the built-in asset (e.g. `piece_wK.png`).
enum CustomAssets {
    private static var cache: [String: UIImage] = [:]
    private static var missing = Set<String>()

    static var folder: URL {
        let url = Paths.documents.appendingPathComponent("Custom", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(_ name: String) -> URL {
        return folder.appendingPathComponent(name + ".png")
    }

    static func image(named name: String) -> UIImage? {
        if let c = cache[name] { return c }
        if missing.contains(name) { return nil }
        if let img = UIImage(contentsOfFile: fileURL(name).path) {
            cache[name] = img
            return img
        }
        missing.insert(name)
        return nil
    }

    static func has(_ name: String) -> Bool {
        return image(named: name) != nil
    }

    private static func changed() {
        cache = [:]
        missing = []
        let v = UserDefaults.standard.integer(forKey: Theme.assetsVersionKey)
        UserDefaults.standard.set(v + 1, forKey: Theme.assetsVersionKey)
    }

    /// Reads an image file, shrinks it and stores it under `name`.
    @discardableResult
    static func importImage(from url: URL, as name: String) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return false }
        let longest = max(img.size.width, img.size.height)
        guard longest > 0 else { return false }
        let scale = min(1, 256 / longest)
        let target = CGSize(width: max(1, (img.size.width * scale).rounded()),
                            height: max(1, (img.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let png = small.pngData() else { return false }
        do {
            try png.write(to: fileURL(name), options: .atomic)
        } catch {
            return false
        }
        changed()
        return true
    }

    static func remove(_ names: [String]) {
        for n in names { try? FileManager.default.removeItem(at: fileURL(n)) }
        changed()
    }

    /// Matches a file name (`wK`, `piece_wK.png`, `brilliant`, `class_brilliant`...) to a slot.
    static func slot(forFile url: URL, among slots: [String]) -> String? {
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        for s in slots {
            let full = s.lowercased()
            var short = full
            for prefix in ["piece_", "class_"] where short.hasPrefix(prefix) {
                short = String(short.dropFirst(prefix.count))
            }
            if base == full || base == short { return s }
        }
        return nil
    }
}
