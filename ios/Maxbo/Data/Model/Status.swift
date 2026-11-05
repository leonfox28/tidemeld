import Foundation

/// Who can see a post, as `visible.type` and `statuses/update` have it.
enum StatusVisibility: Int, Sendable, Hashable, CaseIterable {
    case `public` = 0
    case friends = 6
    case onlyMe = 1
    case fans = 10

    var label: String {
        switch self {
        case .public: "公开"
        case .friends: "好友圈"
        case .onlyMe: "仅自己可见"
        case .fans: "粉丝"
        }
    }

    var symbol: String {
        switch self {
        case .public: "globe.asia.australia"
        case .friends: "person.2"
        case .onlyMe: "lock"
        case .fans: "person.3"
        }
    }

    /// The ones a new post can choose from.
    static let choices: [StatusVisibility] = [.public, .friends, .onlyMe]

    /// Unknown kinds (paid members, groups) count as public.
    static func of(_ code: Int64?) -> StatusVisibility {
        code.flatMap { StatusVisibility(rawValue: Int($0)) } ?? .public
    }
}

/// A Weibo post ("微博").
struct Status: Sendable, Hashable, Identifiable {
    let id: String
    /// The short id used in web URLs (`weibo.com/<uid>/<mblogid>`).
    var mblogId: String? = nil
    /// Nil for deleted or hidden posts, which still appear as retweet sources.
    /// Retweet sources in `statuses/mentions` have only an id and a name.
    var user: WeiboUser? = nil
    var createdAt: Date? = nil
    /// The posting client, e.g. `iPhone客户端`; plain text.
    var source: String? = nil
    /// Where it was posted from, e.g. `发布于 北京`.
    var region: String? = nil
    /// The body as HTML; see `parseStatusText`.
    var text = ""
    /// The body as plain text, in full, as a repost of this one quotes it; nil
    /// when Weibo sent only a cut-short one (long posts in lists).
    var plainText: String? = nil
    /// Short links in [text] and what they resolve to.
    var urls: [URLEntity] = []
    var pics: [PicInfo] = []
    /// How many pictures the post has, which can exceed [pics].
    var picCount = 0
    /// The pictures and videos of a post mixing them, in order; such posts have
    /// neither.
    var mixedMedia: [MixedMedia] = []
    var video: VideoInfo? = nil
    /// A link preview (topic, live stream, …) shown when there is no media.
    var pageCard: PageCard? = nil
    private var retweetedBox: [Status] = []
    var repostsCount = 0
    var commentsCount = 0
    var likesCount = 0
    var liked = false
    /// Marked as an ad by Weibo. Ads are labelled, never hidden (PLAN §2).
    var isAd = false
    /// Pinned atop its author's profile; only set in profile lists.
    var pinned = false
    /// Why someone else's post is on a user's profile: Weibo puts posts they
    /// liked or commented on among their own, labelled like `他10-17赞过的微博`
    /// (PLAN §8). Only set in profile lists.
    var activity: String? = nil
    /// Who can see it. Others' posts are public as far as the viewer knows.
    var visibility: StatusVisibility = .public

    init(
        id: String, mblogId: String? = nil, user: WeiboUser? = nil, createdAt: Date? = nil,
        source: String? = nil, region: String? = nil, text: String = "", plainText: String? = nil,
        urls: [URLEntity] = [], pics: [PicInfo] = [], picCount: Int? = nil,
        mixedMedia: [MixedMedia] = [], video: VideoInfo? = nil, pageCard: PageCard? = nil,
        retweeted: Status? = nil, repostsCount: Int = 0, commentsCount: Int = 0,
        likesCount: Int = 0, liked: Bool = false, isAd: Bool = false, pinned: Bool = false,
        activity: String? = nil, visibility: StatusVisibility = .public
    ) {
        self.id = id
        self.mblogId = mblogId
        self.user = user
        self.createdAt = createdAt
        self.source = source
        self.region = region
        self.text = text
        self.plainText = plainText
        self.urls = urls
        self.pics = pics
        self.picCount = picCount ?? pics.count
        self.mixedMedia = mixedMedia
        self.video = video
        self.pageCard = pageCard
        self.retweetedBox = retweeted.map { [$0] } ?? []
        self.repostsCount = repostsCount
        self.commentsCount = commentsCount
        self.likesCount = likesCount
        self.liked = liked
        self.isAd = isAd
        self.pinned = pinned
        self.activity = activity
        self.visibility = visibility
    }

    /// The post this one reposts.
    var retweeted: Status? {
        get { retweetedBox.first }
        set { retweetedBox = newValue.map { [$0] } ?? [] }
    }

    /// The pictures of a post mixing pictures and videos, in order.
    var mixedPics: [PicInfo] {
        mixedMedia.compactMap { if case .pic(let pic) = $0 { pic } else { nil } }
    }

    /// The videos of a post mixing pictures and videos, in order.
    var mixedVideos: [VideoInfo] {
        mixedMedia.compactMap { if case .video(let video) = $0 { video } else { nil } }
    }

    /// Its video, or with an [index] the one at [index] in [mixedVideos].
    func video(at index: Int?) -> VideoInfo? {
        guard let index else { return video }
        let videos = mixedVideos
        return videos.indices.contains(index) ? videos[index] : nil
    }

    /// [parentURLs] is the `url_struct` of the post retweeting this one, which
    /// also covers the links in this one's text, and [parentPage] its
    /// `page_info`.
    static func from(_ json: JSON?, parentURLs: [JSON] = [], parentPage: JSON? = nil) -> Status? {
        guard let map = json, map.isObject,
            let id = map["idstr"]?.string ?? map["mid"]?.string ?? map["id"]?.string
        else { return nil }
        let pics = picsOf(map)
        let pageInfo = map["page_info"].flatMap { $0.isObject ? $0 : nil }
        let ownURLs = map["url_struct"]?.objects ?? []
        let urlStruct = ownURLs.isEmpty ? parentURLs : ownURLs
        return Status(
            id: id,
            mblogId: map["mblogid"]?.string ?? map["bid"]?.string,
            user: WeiboUser.from(map["user"]) ?? authorOf(map, parentPage: parentPage),
            createdAt: parseWeiboDate(map["created_at"]?.string),
            source: plainTextOfHTML(map["source"]?.string),
            region: map["region_name"]?.string,
            text: textOf(map, urlStruct: urlStruct),
            plainText: map["longText"]?["content"]?.string
                ?? (map["isLongText"]?.bool == true ? nil : map["text_raw"]?.string),
            urls: urlStruct.compactMap(URLEntity.from),
            pics: pics,
            picCount: map["pic_num"]?.int.map { Int($0) } ?? pics.count,
            mixedMedia: (map["mix_media_info"]?["items"]?.objects ?? []).compactMap(MixedMedia.from),
            video: VideoInfo.from(pageInfo: pageInfo),
            pageCard: PageCard.from(pageInfo: pageInfo, urlStruct: urlStruct),
            retweeted: from(map["retweeted_status"], parentURLs: ownURLs, parentPage: pageInfo),
            repostsCount: Int(map["reposts_count"]?.int ?? 0),
            commentsCount: Int(map["comments_count"]?.int ?? 0),
            likesCount: Int(map["attitudes_count"]?.int ?? 0),
            liked: map["attitudes_status"]?.int == 1,
            isAd: isAd(map),
            pinned: map["isTop"]?.int == 1,
            activity: activityOf(map),
            visibility: .of(map["visible"]?["type"]?.int))
    }

    // Not yet confirmed against a real feed ad; see PLAN §8 item 5. Weibo also
    // sets all of these on ordinary posts it classes as advertising content
    // (mark ending `WeiboADNatural`, seen on users' own reposts); those are not
    // ads placed in the feed, so they get no label.
    private static func isAd(_ map: JSON) -> Bool {
        if map["ad_marked"]?.bool == true { return true }
        let mark = map["mark"]?.string ?? ""
        if mark.contains("WeiboADNatural") { return false }
        return map["isAd"]?.bool == true || map["readtimetype"]?.string == "adMblog"
            || mark.contains("mark_ad")
    }

    // Such a label links (`title.structs`) to that day's whole list in Weibo's
    // app, and ends in its length, e.g. `(10)`; we can't open the list, so the
    // length goes. Other titles, such as 公开 in the home feed, link nowhere.
    private static func activityOf(_ map: JSON) -> String? {
        guard let title = map["title"], title.isObject, !(title["structs"]?.objects ?? []).isEmpty,
            let text = title["text"]?.string
        else { return nil }
        let trimmed = text.replacingOccurrences(
            of: #"\(\d+\)$"#, with: "", options: .regularExpression)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Retweet sources in `statuses/mentions` come without `user`. Their
    // retweeting post's page_info is a card for them instead, titled `@author`,
    // which weibo.com shows in their place (PLAN §8).
    private static func authorOf(_ map: JSON, parentPage: JSON?) -> WeiboUser? {
        guard let parentPage, let mblogId = map["mblogid"]?.string,
            parentPage["mblogid"]?.string == mblogId,
            let id = parentPage["uidPageInfo"]?.string,
            let title = parentPage["content1"]?.string, title.hasPrefix("@")
        else { return nil }
        let name = title.dropFirst().trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : WeiboUser(id: id, screenName: name)
    }

    // Retweet sources in `statuses/mentions` come without `text` or `user`,
    // only the plain `text_raw`, cut short with no marker if the post is long
    // (PLAN §8).
    private static func textOf(_ map: JSON, urlStruct: [JSON]) -> String {
        if let text = map["text"]?.string { return text }
        guard let raw = map["text_raw"]?.string else { return "" }
        let html = rawTextAsHTML(raw, urlStruct: urlStruct)
        return map["isLongText"]?.bool == true ? "\(html) ...<span class=\"expand\">展开</span>" : html
    }

    // Links, @mentions and #topics# in plain text. Links stop at the first
    // non-ASCII character: `text_raw` runs them straight into the text.
    private static let rawEntity = try! NSRegularExpression(
        pattern: #"https?://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+"#
            + #"|(?<![A-Za-z0-9])@[A-Za-z0-9_\-\x{4e00}-\x{9fa5}]{1,30}"#
            + #"|#[^#\n]{1,64}#"#)

    /// [raw] as the HTML that `text` would have held, with links titled as
    /// `url_struct` says.
    static func rawTextAsHTML(_ raw: String, urlStruct: [JSON]) -> String {
        let ns = raw as NSString
        var html = ""
        var last = 0
        for match in rawEntity.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            html += escapeHTML(ns.substring(with: NSRange(location: last, length: match.range.location - last)))
            last = match.range.location + match.range.length
            let entity = ns.substring(with: match.range)
            let label = escapeHTML(entity)
            if entity.hasPrefix("@") {
                html += "<a href=\"/n/\(label.dropFirst())\">\(label)</a>"
            } else if entity.hasPrefix("#") {
                let query = entity.addingPercentEncoding(withAllowedCharacters: .formValue) ?? entity
                html += "<a href=\"https://s.weibo.com/weibo?q=\(query)\">\(label)</a>"
            } else {
                let info = urlStruct.first { $0["short_url"]?.string == entity }
                // `url_type_pic` names icons that aren't there, so links go
                // without.
                let title = info?["url_title"]?.string
                html += "<a href=\"\(label)\">\(title.map(escapeHTML) ?? label)</a>"
            }
        }
        html += escapeHTML(ns.substring(from: last))
        return html
    }
}

/// A short link (`t.cn/…`) in a status body. [pics] are the pictures a
/// "查看图片" link shows, such as those of a comment or of a repost along the
/// chain.
struct URLEntity: Sendable, Hashable {
    let shortURL: String
    var longURL: String? = nil
    var title: String? = nil
    var pics: [PicInfo] = []

    static func from(_ json: JSON) -> URLEntity? {
        guard let short = json["short_url"]?.url else { return nil }
        return URLEntity(
            shortURL: short,
            longURL: json["long_url"]?.url ?? json["ori_url"]?.url,
            title: json["url_title"]?.string,
            pics: picsOf(json))
    }
}

/// The video attached to a status.
struct VideoInfo: Sendable, Hashable {
    var coverURL: String? = nil
    /// Length in seconds.
    var duration: Int? = nil
    var aspectRatio: Double? = nil
    /// Playable mp4 streams, preferred first. They are signed and expire about
    /// an hour after Weibo sent them; see `resolveVideoURL`.
    var streamURLs: [String] = []

    // In order of preference: 720p is plenty on a phone; H.265 renditions are
    // skipped as Android didn't decode them everywhere, and to match it.
    private static let streamKeys = ["mp4_720p_mp4", "mp4_hd_url", "mp4_sd_url"]

    static func from(pageInfo: JSON?) -> VideoInfo? {
        guard let pageInfo, pageInfo["object_type"]?.string == "video" || pageInfo["type"]?.string == "video" else { return nil }
        let media = pageInfo["media_info"]
        let big = media?["big_pic_info"]?["pic_big"] ?? pageInfo["pic_info"]?["pic_big"] ?? pageInfo["page_pic"]
        let width = big?["width"]?.int ?? 0
        let height = big?["height"]?.int ?? 0
        var streams: [String] = []
        for key in streamKeys {
            if let url = media?[key]?.url, !streams.contains(url) { streams.append(url) }
        }
        for url in [pageInfo["urls"]?["mp4_720p_mp4"]?.url, pageInfo["urls"]?["mp4_hd_mp4"]?.url,
                    media?["stream_url_hd"]?.url, pageInfo["urls"]?["mp4_ld_mp4"]?.url, media?["stream_url"]?.url].compactMap({ $0 }) {
            if !streams.contains(url) { streams.append(url) }
        }
        for url in playbackURLs(media?["playback_list"]) where !streams.contains(url) {
            streams.append(url)
        }
        return VideoInfo(
            coverURL: pageInfo["page_pic"]?.url ?? big?["url"]?.url,
            duration: media?["duration"]?.int.map { Int($0) },
            aspectRatio: width > 0 && height > 0 ? Double(width) / Double(height) : nil,
            streamURLs: streams.map(https))
    }

    /// The plain mp4 entries of `playback_list`, best quality first; it also
    /// lists scrubbing thumbnails and may list adaptive streams.
    private static func playbackURLs(_ list: JSON?) -> [String] {
        (list?.objects ?? []).compactMap { item -> (String, Int64)? in
            guard let info = item["play_info"], info.isObject,
                info["mime"]?.string == "video/mp4", info["protocol"]?.string != "dash",
                let url = info["url"]?.url
            else { return nil }
            return (url, item["meta"]?["quality_index"]?.int ?? 0)
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }
}

/// An item of a post mixing pictures and videos (`mix_media_info`).
enum MixedMedia: Sendable, Hashable {
    case pic(PicInfo)
    case video(VideoInfo)

    /// Items hold a `pic_infos` entry or a `page_info` as their `data`.
    static func from(_ json: JSON) -> MixedMedia? {
        let data = json["data"]
        switch json["type"]?.string {
        case "pic": return PicInfo.from(data, id: json["id"]?.string).map(MixedMedia.pic)
        case "video": return VideoInfo.from(pageInfo: data).map(MixedMedia.video)
        default: return nil
        }
    }
}

/// A link preview such as a topic or live stream.
struct PageCard: Sendable, Hashable {
    let title: String
    var description: String? = nil
    var imageURL: String? = nil

    /// Nil when the card would only repeat the title of a link in the text,
    /// [urlStruct] describing those links: a `webpage` card can come with no
    /// picture or description (PLAN §8).
    static func from(pageInfo: JSON?, urlStruct: [JSON] = []) -> PageCard? {
        guard let pageInfo, pageInfo["object_type"]?.string != "video", pageInfo["type"]?.string != "video",
            let title = pageInfo["page_title"]?.string
        else { return nil }
        let description = pageInfo["page_desc"]?.string ?? pageInfo["content2"]?.string
        let imageURL = pageInfo["page_pic"]?.url
        if description == nil, imageURL == nil,
            urlStruct.contains(where: { $0["url_title"]?.string == title })
        {
            return nil
        }
        return PageCard(title: title, description: description, imageURL: imageURL)
    }
}
