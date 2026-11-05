import Foundation
import Observation
import SwiftUI

/// Light, dark, or as the system has it.
enum ThemeMode: String, Sendable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Which picture renditions to load.
enum ImageQuality: String, Sendable, CaseIterable, Identifiable {
    case dataSaver, standard, original

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dataSaver: "省流量"
        case .standard: "标准"
        case .original: "原图"
        }
    }

    var description: String {
        switch self {
        case .dataSaver: "列表里的图片用较小的尺寸"
        case .standard: "按屏幕清晰度选择尺寸"
        case .original: "查看大图时加载原图，可能有好几 MB"
        }
    }

    /// The physical pixels an in-list picture [points] across should cover, on
    /// a screen of [scale] pixels per point.
    func listPixels(_ points: Double, scale: Double) -> Double {
        points * (self == .dataSaver ? 1 : scale)
    }

    /// The rendition the image viewer shows.
    func viewerVariant(_ pic: PicInfo) -> PicVariant {
        self == .original ? (pic.largest ?? pic.viewerVariant) : pic.viewerVariant
    }
}

/// How large text is, relative to the text size set on the device: the
/// standard size, or up to two steps either way along Dynamic Type's sizes.
enum TextSize: String, Sendable, CaseIterable, Identifiable {
    case extraSmall, small, standard, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .extraSmall: "特小"
        case .small: "小"
        case .standard: "标准"
        case .large: "大"
        case .extraLarge: "特大"
        }
    }

    var steps: Int {
        switch self {
        case .extraSmall: -2
        case .small: -1
        case .standard: 0
        case .large: 1
        case .extraLarge: 2
        }
    }

    /// The device's text size, [system], moved by this size's steps.
    func applied(to system: DynamicTypeSize) -> DynamicTypeSize {
        let sizes = DynamicTypeSize.allCases
        let index = sizes.firstIndex(of: system) ?? sizes.firstIndex(of: .large)!
        return sizes[min(max(index + steps, 0), sizes.count - 1)]
    }
}

/// User preferences, kept on the device only.
struct AppSettings: Sendable, Equatable {
    var feedSelection: FeedSelection = .all
    var themeMode: ThemeMode = .system
    var textSize: TextSize = .standard
    var imageQuality: ImageQuality = .standard
    /// Whether a live photo's motion plays on its own, once and without sound,
    /// when the image viewer shows it; otherwise only when asked for.
    var autoplayLivePhotos = false
    /// How large the picture disk cache may grow before the oldest pictures
    /// are deleted.
    var imageCacheLimitMB = 300

    static let imageCacheLimitChoices = [100, 300, 500, 1024]
}

/// Where settings are kept between launches.
protocol SettingsStorage {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

final class DefaultsSettingsStorage: SettingsStorage {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> AppSettings {
        var settings = AppSettings()
        let d = defaults
        if let v = d.string(forKey: "feedSelection").flatMap(FeedSelection.init) { settings.feedSelection = v }
        if let v = d.string(forKey: "themeMode").flatMap(ThemeMode.init) { settings.themeMode = v }
        if let v = d.string(forKey: "textSize").flatMap(TextSize.init) { settings.textSize = v }
        if let v = d.string(forKey: "imageQuality").flatMap(ImageQuality.init) { settings.imageQuality = v }
        settings.autoplayLivePhotos = d.bool(forKey: "autoplayLivePhotos")
        let limit = d.integer(forKey: "imageCacheLimitMB")
        if AppSettings.imageCacheLimitChoices.contains(limit) { settings.imageCacheLimitMB = limit }
        return settings
    }

    func save(_ settings: AppSettings) {
        let d = defaults
        d.set(settings.feedSelection.rawValue, forKey: "feedSelection")
        d.set(settings.themeMode.rawValue, forKey: "themeMode")
        d.set(settings.textSize.rawValue, forKey: "textSize")
        d.set(settings.imageQuality.rawValue, forKey: "imageQuality")
        d.set(settings.autoplayLivePhotos, forKey: "autoplayLivePhotos")
        d.set(settings.imageCacheLimitMB, forKey: "imageCacheLimitMB")
    }
}

@MainActor @Observable
final class SettingsController {
    private(set) var settings: AppSettings
    @ObservationIgnored private let storage: SettingsStorage
    @ObservationIgnored var onChange: ((AppSettings) -> Void)?

    init(storage: SettingsStorage) {
        self.storage = storage
        settings = storage.load()
    }

    /// Changes the settings with [change]; it takes effect at once and is saved.
    func update(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        storage.save(next)
        onChange?(next)
    }
}
