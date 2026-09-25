import SwiftUI

enum WallpaperSpaceScope: String, CaseIterable, Identifiable {
    case current
    case visited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: "Current Space"
        case .visited: "Every Space You Visit"
        }
    }
}

/// User preferences backed by UserDefaults; every property writes through on change.
@Observable
class AppSettings {
    static let shared = AppSettings()

    var hasCompletedWizard: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedWizard, forKey: "hasCompletedWizard")
        }
    }

    /// Physical gap between adjacent displays in screen points. 0 disables bezel compensation.
    /// Displays without an entry in `bezelWidths` get half of this on each side.
    var bezelGap: Double {
        didSet {
            UserDefaults.standard.set(bezelGap, forKey: "bezelGap")
        }
    }

    /// Per-display frame widths in screen points, keyed by `CGDirectDisplayID` as a string.
    /// New entries hold `left`, `right`, `top` and `bottom`. Legacy symmetric
    /// `horizontal` and `vertical` values remain readable for migration.
    var bezelWidths: [String: [String: Double]] {
        didSet {
            UserDefaults.standard.set(bezelWidths, forKey: "bezelWidths")
        }
    }

    /// When false the editor shows one pair of bezel sliders that writes to every display.
    var bezelPerDisplay: Bool {
        didSet {
            UserDefaults.standard.set(bezelPerDisplay, forKey: "bezelPerDisplay")
        }
    }

    /// The public wallpaper API can set only the active Space. In visited mode the
    /// last render is reapplied whenever macOS reports that another Space became active.
    var wallpaperSpaceScope: WallpaperSpaceScope {
        didSet {
            UserDefaults.standard.set(wallpaperSpaceScope.rawValue, forKey: "wallpaperSpaceScope")
        }
    }

    /// Frame widths of one display, falling back to half the uniform gap on every edge.
    func bezel(for displayID: CGDirectDisplayID) -> Bezel {
        let entry = bezelWidths[String(displayID)]
        let fallback = bezelGap / 2
        let legacyHorizontal = entry?["horizontal"] ?? fallback
        let legacyVertical = entry?["vertical"] ?? fallback
        return Bezel(
            left: CGFloat(entry?["left"] ?? legacyHorizontal),
            right: CGFloat(entry?["right"] ?? legacyHorizontal),
            top: CGFloat(entry?["top"] ?? legacyVertical),
            bottom: CGFloat(entry?["bottom"] ?? legacyVertical)
        )
    }

    /// Whether this display has already been saved in the four-edge format.
    func hasPerEdgeBezel(for displayID: CGDirectDisplayID) -> Bool {
        guard let entry = bezelWidths[String(displayID)] else { return false }
        return ["left", "right", "top", "bottom"].allSatisfy { entry[$0] != nil }
    }

    /// Stores one display's frame widths, clamped to 0...500 points.
    func setBezel(_ bezel: Bezel, for displayID: CGDirectDisplayID) {
        bezelWidths[String(displayID)] = [
            "left": Double(max(0, min(bezel.left, 500))),
            "right": Double(max(0, min(bezel.right, 500))),
            "top": Double(max(0, min(bezel.top, 500))),
            "bottom": Double(max(0, min(bezel.bottom, 500))),
        ]
    }

    /// Restores every setting from UserDefaults and drops stale keys.
    init() {
        self.hasCompletedWizard = UserDefaults.standard.bool(forKey: "hasCompletedWizard")
        self.bezelGap = UserDefaults.standard.double(forKey: "bezelGap")
        self.bezelWidths = UserDefaults.standard.dictionary(forKey: "bezelWidths") as? [String: [String: Double]] ?? [:]
        self.bezelPerDisplay = UserDefaults.standard.bool(forKey: "bezelPerDisplay")
        self.wallpaperSpaceScope = WallpaperSpaceScope(
            rawValue: UserDefaults.standard.string(forKey: "wallpaperSpaceScope") ?? ""
        ) ?? .current

        // Clears keys no current setting reads.
        UserDefaults.standard.removeObject(forKey: "showInMenuBar")
        UserDefaults.standard.removeObject(forKey: "launchAtLogin")
        UserDefaults.standard.removeObject(forKey: "appearanceMode")
    }
}
