import Foundation
import zlib

enum PicType: Sendable, Hashable {
    case pic, gif, livePhoto
}

/// One rendition of a picture.
struct PicVariant: Sendable, Hashable {
    let url: String
    let width: Int
    let height: Int
}

/// A picture attached to a status, in the renditions Weibo offers.
struct PicInfo: Sendable, Hashable, Identifiable {
    let id: String
    let type: PicType
    /// Renditions suitable for in-list display, smallest first.
    let variants: [PicVariant]
    /// The full-size picture, which may be many megabytes; only for viewing.
    var largest: PicVariant? = nil
    /// The moving part of a live photo: a signed URL that, like a video's,
    /// expires about an hour after the status loaded (PLAN §8).
    var liveVideo: String? = nil

    /// Width over height of the picture, if known.
    var aspectRatio: Double? {
        let v = largest ?? variants.last!
        return v.width > 0 && v.height > 0 ? Double(v.width) / Double(v.height) : nil
    }

    /// Much taller than wide; shown cropped with a badge.
    var isLong: Bool { (aspectRatio ?? 1) < 1.0 / 3 }

    /// The smallest rendition whose shorter side covers [pixels], or the largest
    /// available. A rendition of unknown size is taken to cover it.
    func variant(for pixels: Double) -> PicVariant {
        for v in variants {
            let shorter = min(v.width, v.height)
            if Double(shorter) >= pixels || shorter == 0 { return v }
        }
        return variants.last!
    }

    /// What the image viewer shows: the largest list rendition (up to about
    /// 2000 px wide, enough for a phone screen), or for a GIF the full file, as
    /// smaller renditions may not be animated.
    var viewerVariant: PicVariant {
        type == .gif ? (largest ?? variants.last!) : variants.last!
    }

    // Names don't reliably say how big a rendition is (`original` is often a
    // mid-size crop), so variants are chosen by their actual size instead.
    private static let listVariants = ["thumbnail", "bmiddle", "large", "mw2000"]
    private static let fullVariants = ["largest", "original", "woriginal"]

    /// A picture known only by its URL, such as one linked from a status body.
    static func fromURL(_ url: String) -> PicInfo {
        let path = URL(string: url)?.path ?? ""
        return PicInfo(
            id: url, type: path.hasSuffix(".gif") ? .gif : .pic,
            variants: [PicVariant(url: url, width: 0, height: 0)])
    }

    /// Mobile public posts use a `pics` array, with dimensions under `geo`.
    static func fromMobile(_ json: JSON) -> PicInfo? {
        func mobileVariant(_ value: JSON?) -> PicVariant? {
            guard let url = value?["url"]?.url else { return nil }
            return PicVariant(url: url,
                width: Int(value?["geo"]?["width"]?.int ?? value?["width"]?.int ?? 0),
                height: Int(value?["geo"]?["height"]?.int ?? value?["height"]?.int ?? 0))
        }
        let variants = [mobileVariant(json), mobileVariant(json["large"])].compactMap { $0 }
        guard let first = variants.first else { return nil }
        return PicInfo(id: json["pid"]?.string ?? first.url,
            type: URL(string: first.url)?.path.hasSuffix(".gif") == true ? .gif : .pic,
            variants: variants, largest: variants.last)
    }

    /// [id] names the picture when the JSON itself doesn't, as in comment
    /// pictures, which are keyed by id.
    static func from(_ json: JSON?, id: String? = nil) -> PicInfo? {
        guard let map = json, map.isObject else { return nil }
        let picId = map["pic_id"]?.string ?? map["object_id"]?.string ?? id
        var variants = listVariants.compactMap { variant(map[$0]) }
        // Without sizes (comment pictures), keep the smallest-first key order.
        if variants.allSatisfy({ $0.width > 0 }) { variants.sort { $0.width < $1.width } }
        guard let picId, !variants.isEmpty else { return nil }
        let type: PicType =
            switch map["type"]?.string {
            case "gif": .gif
            case "livephoto": .livePhoto
            default: .pic
            }
        let largest = fullVariants.compactMap { variant(map[$0]) }.max { $0.width < $1.width }
        return PicInfo(
            id: picId, type: type, variants: variants, largest: largest,
            liveVideo: type == .livePhoto ? map["video"]?.url.map { https($0) } : nil)
    }

    /// A picture known only by its [pid], such as one on a comment just sent, in
    /// the renditions comment pictures come in, at the address weibo.com gives
    /// it; nil for an older kind of pid.
    static func fromPid(_ pid: String) -> PicInfo? {
        let chars = Array(pid)
        guard chars.count >= 32, chars[9] == "y" else { return nil }
        let crc = pid.data(using: .isoLatin1).map { data in
            data.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)) }
        } ?? 0
        let host = "https://wx\((crc & 3) + 1).sinaimg.cn"
        let type: PicType = chars[21] == "g" ? .gif : .pic
        let file = "\(pid).\(type == .gif ? "gif" : "jpg")"
        func variant(_ name: String) -> PicVariant {
            PicVariant(url: "\(host)/\(name)/\(file)", width: 0, height: 0)
        }
        return PicInfo(
            id: pid, type: type, variants: listVariants.prefix(3).map(variant),
            largest: variant("woriginal"))
    }

    private static func variant(_ json: JSON?) -> PicVariant? {
        guard let url = json?["url"]?.url else { return nil }
        return PicVariant(
            url: url, width: Int(json?["width"]?.int ?? 0), height: Int(json?["height"]?.int ?? 0))
    }
}

/// The pictures of a JSON object holding `pic_infos` keyed by id, in the display
/// order of its `pic_ids`.
func picsOf(_ json: JSON) -> [PicInfo] {
    guard let infos = json["pic_infos"]?.object else {
        return (json["pics"]?.objects ?? []).compactMap(PicInfo.fromMobile)
    }
    let order = json["pic_ids"]?.array?.compactMap(\.string) ?? []
    return (order.isEmpty ? Array(infos.keys).sorted() : order).compactMap {
        PicInfo.from(infos[$0], id: $0)
    }
}
