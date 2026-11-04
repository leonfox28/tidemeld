import Foundation
import Testing

@testable import Maxbo

/// Synthetic JSON from a Swift literal.
func json(_ literal: String) -> JSON { JSON.parse(literal)! }

struct ModelTests {
    @Test func parsesAPlainStatusKeepingIdsAsStrings() throws {
        let status = try #require(
            Status.from(
                json(
                    """
                    {"idstr":"5212345678901234","id":5212345678901234,"mblogid":"Abc","created_at":"Mon Oct 12 13:17:46 +0800 2026",
                     "user":{"id":1234567890,"screen_name":"示例","avatar_large":"https://tva1.sinaimg.cn/a.jpg?Expires=1&ssig=x&KID=y","verified":true,"verified_type":0},
                     "text":"你好","source":"<a href=\\"x\\">iPhone客户端</a>","region_name":"发布于 北京",
                     "reposts_count":"3","comments_count":4,"attitudes_count":5,"attitudes_status":1}
                    """)))
        #expect(status.id == "5212345678901234")
        #expect(status.user?.id == "1234567890")
        #expect(status.user?.verifiedType == 0)
        #expect(status.source == "iPhone客户端")
        #expect(status.repostsCount == 3)
        #expect(status.liked)
        #expect(status.createdAt == Date(timeIntervalSince1970: 1_791_782_266))
    }

    @Test func toleratesMissingAndMistypedFields() {
        #expect(Status.from(json(#"{"text":"no id"}"#)) == nil)
        let status = Status.from(json(#"{"id":"1","user":"nobody","pic_infos":[],"reposts_count":"many"}"#))
        #expect(status?.user == nil)
        #expect(status?.repostsCount == 0)
        #expect(status?.pics.isEmpty == true)
    }

    @Test func hugeNumbersAreCappedNotACrash() {
        let read = json(#"{"big":1e19,"small":-1e19,"half":2.5}"#)
        #expect(read["big"]?.int == .max)
        #expect(read["small"]?.int == .min)
        #expect(read["half"]?.int == 2)
    }

    @Test func ordersPicturesByPicIdsAndReadsLivePhotos() throws {
        let status = try #require(
            Status.from(
                json(
                    """
                    {"id":"1","pic_ids":["b","a"],"pic_num":3,
                     "pic_infos":{
                       "a":{"pic_id":"a","type":"gif","thumbnail":{"url":"https://wx1.sinaimg.cn/thumbnail/a.gif","width":90,"height":90},
                            "largest":{"url":"https://wx1.sinaimg.cn/large/a.gif","width":900,"height":900}},
                       "b":{"pic_id":"b","type":"livephoto","video":"http://video.weibo.com/media/play?livephoto=x&Expires=9",
                            "bmiddle":{"url":"https://wx1.sinaimg.cn/bmiddle/b.jpg","width":440,"height":2000},
                            "thumbnail":{"url":"https://wx1.sinaimg.cn/thumbnail/b.jpg","width":90,"height":409}}}}
                    """)))
        #expect(status.pics.map(\.id) == ["b", "a"])
        #expect(status.picCount == 3)
        #expect(status.pics[0].type == .livePhoto)
        #expect(status.pics[0].liveVideo == "https://video.weibo.com/media/play?livephoto=x&Expires=9")
        #expect(status.pics[0].isLong)
        #expect(status.pics[0].variant(for: 100).url == "https://wx1.sinaimg.cn/bmiddle/b.jpg")
        // A GIF's viewer shows the whole file, as smaller renditions may not move.
        #expect(status.pics[1].viewerVariant.url == "https://wx1.sinaimg.cn/large/a.gif")
    }

    @Test func labelsAdsButNotWeibosClassedContent() {
        #expect(Status.from(json(#"{"id":"1","isAd":true}"#))?.isAd == true)
        #expect(Status.from(json(#"{"id":"1","readtimetype":"adMblog"}"#))?.isAd == true)
        #expect(
            Status.from(json(#"{"id":"1","isAd":true,"mark":"999_reallog_mark_ad:999|WeiboADNatural"}"#))?.isAd == false)
    }

    @Test func readsVideosAndMixedMedia() throws {
        let status = try #require(
            Status.from(
                json(
                    """
                    {"id":"1","mix_media_info":{"items":[
                      {"type":"video","data":{"object_type":"video","page_pic":"https://wx1.sinaimg.cn/cover.jpg",
                        "media_info":{"duration":61,"mp4_hd_url":"http://f.video.weibocdn.com/hd.mp4","mp4_720p_mp4":"http://f.video.weibocdn.com/720.mp4",
                          "playback_list":[{"meta":{"quality_index":3},"play_info":{"mime":"video/mp4","url":"http://f.video.weibocdn.com/1080.mp4"}},
                                           {"meta":{"quality_index":9},"play_info":{"mime":"image/jpeg","url":"http://x/thumb.jpg"}}]}}},
                      {"type":"pic","id":"p","data":{"thumbnail":{"url":"https://wx1.sinaimg.cn/thumbnail/p.jpg","width":1,"height":1}}}]}}
                    """)))
        #expect(status.mixedMedia.count == 2)
        let video = try #require(status.video(at: 0))
        #expect(video.duration == 61)
        #expect(
            video.streamURLs == [
                "https://f.video.weibocdn.com/720.mp4", "https://f.video.weibocdn.com/hd.mp4",
                "https://f.video.weibocdn.com/1080.mp4",
            ])
        #expect(status.mixedPics.map(\.id) == ["p"])
    }

    @Test func aRetweetSourceInMentionsGetsTextAndAuthorFromTheRepost() throws {
        let status = try #require(
            Status.from(
                json(
                    """
                    {"id":"2","text":"转发","url_struct":[{"short_url":"http://t.cn/A1","url_title":"微博正文"}],
                     "page_info":{"object_type":"meaasgeObjType","content1":"@原作者","mblogid":"M1","uidPageInfo":"99"},
                     "retweeted_status":{"id":"1","mblogid":"M1","text":"","text_raw":"看 http://t.cn/A1 和 @朋友 #话题#","isLongText":true}}
                    """)))
        let source = try #require(status.retweeted)
        #expect(source.user == WeiboUser(id: "99", screenName: "原作者"))
        #expect(
            source.text
                == "看 <a href=\"http://t.cn/A1\">微博正文</a> 和 <a href=\"/n/朋友\">@朋友</a> "
                + "<a href=\"https://s.weibo.com/weibo?q=%23%E8%AF%9D%E9%A2%98%23\">#话题#</a> ...<span class=\"expand\">展开</span>")
        #expect(source.plainText == nil)
    }

    @Test func readsTheActivityLabelOnAProfile() {
        let status = Status.from(
            json(#"{"id":"1","title":{"text":"他10-17赞过的微博(10)","structs":[{"name":"他10-17赞过的微博(10)"}]}}"#))
        #expect(status?.activity == "他10-17赞过的微博")
        #expect(Status.from(json(#"{"id":"1","title":{"text":"公开"}}"#))?.activity == nil)
    }

    @Test func aFeedPageContinuesFromMaxIdStr() {
        let page = Paged<Status>.feed(json(#"{"statuses":[{"id":"1"},{"no":"id"}],"max_id":5,"max_id_str":"5212345678901234567"}"#))
        #expect(page.items.map(\.id) == ["1"])
        #expect(page.nextCursor == "5212345678901234567")
        #expect(Paged<Status>.feed(json(#"{"statuses":[{"id":"1"}],"max_id":0}"#)).nextCursor == nil)
    }

    @Test func aCommentJustSentHasItsPicturesByPid() throws {
        let pid = "0000aaaaay1bbbbbbbbbbj0000000001"
        let comment = try #require(
            Comment.from(
                json(
                    """
                    {"idstr":"7","text":"看<a href=/n/朋友 usercard=\\"name=朋友\\">@朋友</a> <a target=\\"_blank\\" href=\\"https://t.cn/xyz\\"><img class=\\"icon-link\\" src=\\"https://h5.sinaimg.cn/l.png\\">网页链接</a>",
                     "pic_num":1,"pic_ids":["\(pid)"]}
                    """)))
        let pic = try #require(comment.pics.first)
        #expect(pic.variant(for: 300).url == "https://wx3.sinaimg.cn/thumbnail/\(pid).jpg")
        #expect(pic.largest?.url == "https://wx3.sinaimg.cn/woriginal/\(pid).jpg")
        // The link to the picture goes; the mention stays.
        #expect(comment.text == "看<a href=/n/朋友 usercard=\"name=朋友\">@朋友</a>")
    }

    @Test func aPidSaysWhetherThePictureIsAGIF() {
        let pic = PicInfo.fromPid("0000aaaaay1bbbbbbbbbbg0000000002")
        #expect(pic?.type == .gif)
        #expect(pic?.largest?.url == "https://wx4.sinaimg.cn/woriginal/0000aaaaay1bbbbbbbbbbg0000000002.gif")
        #expect(PicInfo.fromPid("6a8b1d2fgw1e2abc") == nil)
    }

    @Test func skipsThePictureOfTheCommentAReplyAnswers() {
        let entry = #"{"short_url":"http://t.cn/root","pic_infos":{"root":{"thumbnail":{"url":"https://wx4.sinaimg.cn/thumbnail/root.jpg"}}}}"#
        let reply = #"{"id":"1","text_raw":"回复","pic_num":0,"url_struct":["# + entry + "]}"
        #expect(Comment.from(json(reply))?.pics.isEmpty == true)
    }

    @Test func readsProfilesAndHotSearch() {
        let profile = UserProfile.from(
            json(#"{"user":{"id":1,"screen_name":"x","cover_image_phone":"https://a/1.jpg;https://a/2.jpg","description":"  ","following":true}}"#))
        #expect(profile?.coverURL == "https://a/1.jpg")
        #expect(profile?.description == nil)
        #expect(profile?.following == true)
        #expect(UserProfile.from(json(#"{"user":{}}"#)) == nil)

        let hot = HotSearch.from(
            json(
                ##"{"hotgov":{"word":"#置顶#"},"realtime":[{"word":"热词","word_scheme":"#热词#","realpos":1,"num":12345},{"word":"插入","is_ad":1}]}"##
            ))
        #expect(hot.pinned.map(\.word) == ["置顶"])
        #expect(hot.items[0].query == "#热词#")
        #expect(hot.items[1].badge == "荐")
    }

    @Test func readsUnreadKindsAndLikeNotices() {
        #expect(UnreadNotices.from(json(#"{"cmt":2,"mention_cmt":0,"attitude":"1"}"#)).kinds == [.comments, .likes])
        let like = LikeNotice.from(json(#"{"idStr":"9","status":{"id":"1","text":"x"}}"#))
        #expect(like?.id == "9")
        #expect(like?.statusComplete == false)
    }
}
