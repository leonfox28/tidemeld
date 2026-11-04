# iOS 版审查（2026-11-04）

用户要求审查 iOS 版还有哪里没完善。做法：按区域（网络与会话、时间线与媒体、详情与写操作、外壳与其余页面）把 `ios/Maxbo/` 和 Kotlin 版逐个对照读代码，没在模拟器上操作。审查时 Android 从 2026-10-25（v0.13.1）起没有改动，iOS 是照着这一版翻译的。

总体：Kotlin 版的每个页面和路由在 iOS 都有；端点和参数逐个对得上；写请求不重发；日志里没有 Cookie 值和正文；没有轮询和后台请求。单元测试 52 个通过，Debug 和 Release 都能编译。

下面每条一个编号，修好后在「状态」里写上提交。行号是审查时的。

## A. 会影响使用的 bug

| 编号 | 问题 | 位置 | 状态 |
|---|---|---|---|
| A1 | 打开带红点的通知页签，红点清了但列表不刷新：`markRead` 改了 `.task` 的 id，进行中的刷新被取消，错误被 `try?` 吞掉。Kotlin v0.12.1 修过同一个问题（PLAN §11），刷新放在页面的 scope 里 | `UI/Notifications/NotificationsPage.swift:147-151`；Kotlin `NotificationsPage.kt:164-176` | 已修 |
| A2 | 视频还在加载（例如地址过期正在重新请求）时关掉页面，之后会在后台开始播放，停不下来：加载的 `Task` 没有取消 | `UI/Media/VideoPlayerPage.swift:31-66`；Kotlin `VideoPlayerPage.kt:95,151-154` | 已修 |
| A3 | 看图打开后 0.4 秒内关掉，实况照片的自动播放仍会在后台下载并静音播放：延时的 `Task` 没有取消 | `UI/Media/ImageViewer.swift:83-87`；Kotlin `ImageViewerPage.kt:94-97` | 已修 |
| A4 | 看图打开长图时铺满宽度，`scrollViewDidZoom` 把这当成放大，翻页被禁用，左右滑不到下一张 | `UI/Media/ZoomableImage.swift:84-100`、`ImageViewer.swift:36`；Kotlin `ImageViewerPage.kt:182-191` | 待修 |
| A5 | 发微博、写评论选图后，图片在后台读入，期间没有提示、「发送」可点：这时发出去会少图，或者图片落进下一条草稿 | `UI/Compose/ComposePage.swift:78-82,106-117`、`UI/Interactions/CommentComposer.swift:106-117` | 待修 |
| A6 | Cookie 和 XSRF 在进限流队列之前就写进请求头，Kotlin 是轮到发送时才读：退出后排队的请求仍带旧 `SUB`；续期后排队的读请求多发一次，写请求失败；排队期间换了的 `XSRF-TOKEN` 用不上 | `Core/Net/WeiboHTTP.swift:57-60`；Kotlin `WeiboHttp.kt:82-86,157-172` | 待修 |
| A7 | 没有设置 `AVAudioSession`：静音键打开时视频和带声音的实况照片没有声音；画中画要 `.playback` 类别和后台音频模式，现在用不了（IOS.md §3 写了支持）。模拟器没有静音键，要真机确认 | 全局；`UI/Media/VideoPlayerPage.swift:112` | 待修 |
| A8 | 登录页的错误提示看不见：提示条挂在 `TabView` 上，被登录弹层盖住。Kotlin 在登录页自己的提示条里显示 | `UI/Auth/LoginPage.swift:91-93`、`App/RootView.swift:59`；Kotlin `LoginPage.kt:93,203` | 待修 |
| A9 | 退出登录时不清各页签的页面栈，换账号后在别的页签还能返回到上一个账号打开的微博或主页 | `UI/Navigation/Router.swift:92`、`UI/Profile/MePage.swift:59` | 待修 |
| A10 | 换账号后通知列表还是上一个账号的：列表放在 `.id(account.uid)` 外面，登录后 `start()` 见已加载过就不再加载。**Kotlin 也有**（`NotificationsPage.kt:114,152`，ViewModel 在首页的 store 里），两边一起改 | `UI/Notifications/NotificationsPage.swift:75,90,293` | 已修 |

## B. 违反「请求只在用户操作时发起」

| 编号 | 问题 | 位置 | 状态 |
|---|---|---|---|
| B1 | `LoadMoreFooter` 在 `.onAppear` 里加载下一页：第一页不满一屏时不用滑动就请求第 2 页（楼中楼、按热度的评论常见）。Kotlin 只在滚动位置变化时触发，短列表等按钮；iOS 的注释也是这么写的 | `UI/Widget/LoadState.swift:56-61`；Kotlin `LoadState.kt:42-62` | 待修 |

## C. 性能和内存

| 编号 | 问题 | 位置 | 状态 |
|---|---|---|---|
| C1 | 图片滚出屏幕后下载和解码不取消（共享下载的 `Task` 不接调用方的取消），快速滑动时把经过的图都下载一遍。Coil 会取消 | `Core/Media/ImageLoader.swift:66,146-151` | 待修 |
| C2 | GIF 不降采样，按原尺寸逐帧解码（最多 300 帧）；看图最大 8192 px 的图和列表缩略图挤同一个 96 MB 内存缓存 | `ImageLoader.swift:104,123-139`、`UI/Media/ImageViewer.swift:133` | 待修 |
| C3 | 每加载完一个表情，屏幕上所有带表情的正文都重绘、重新解析 HTML（共用一个被观察的字典，解析没缓存）。Kotlin 每段正文只解析一次 | `UI/Widget/Text/StatusText.swift:7-34,56,88-95` | 待修 |
| C4 | 清除图片缓存在主线程同步执行 | `UI/Settings/SettingsPage.swift:66`、`ImageLoader.swift:91-94` | 待修 |
| C5 | 选图时复制到 `tmp/drafts/` 的文件从不删除（移除图片、发送后、换账号） | `UI/Compose/ComposeDraft.swift:25-33` | 待修 |
| C6 | 看图的占位图加载 `pic.variants.first`（最小的那张），列表一般没加载过它，等于多一个请求，放大时还比缩略图糊。Kotlin 显示转圈 | `UI/Media/ImageViewer.swift:116`；Kotlin `ImageViewerPage.kt:207-208` | 待修 |

## D. 和 Android 不一致或缺少的

| 编号 | 问题 | 位置 | 状态 |
|---|---|---|---|
| D1 | 应用内浏览器：返回按钮直接关页，不是网页后退；有历史时没有「关闭」按钮 | `UI/Web/InAppBrowser.swift:17-34`；Kotlin `WebPage.kt:83-90,102` | 待修 |
| D2 | 转发一条转发时光标在 `//@…` 后面，Kotlin 放在最前（`TextRange(0)`） | `UI/Compose/ComposePage.swift:157,192-194`；Kotlin `StatusWrites.kt:170-178` | 待修 |
| D3 | 发微博弹层里点「去验证」会关掉弹层（`SendError` 调 `dismiss()`），回来要重新打开。Kotlin 发微博是页面，验证完回到原处 | `ComposePage.swift:27`、`CommentComposer.swift:188-192`；Kotlin `ComposePage.kt:198-201` | 待修 |
| D4 | 评论的图片读文件失败时提示「网络连接失败」，Kotlin 是「图片读取失败」 | `CommentComposer.swift:161,172`；Kotlin `PicturePicker.kt:88-101` | 待修 |
| D5 | 转发被截断的转发时，取全文的 `Task` 不跟页面走，离开页面后转发弹层仍会弹出 | `UI/Status/StatusActions.swift:81-95`；Kotlin `StatusWrites.kt:91-114` | 待修 |
| D6 | 发送时没有「正在上传图片 i/n」 | `ComposePage.swift:27-31`；Kotlin `ComposePage.kt:189-197` | 待修 |
| D7 | 正在删除时再点删除，还会弹确认，确认后什么也不做。Kotlin 先查 `deleting` | `StatusActions.swift:110-116`；Kotlin `StatusWrites.kt:121-125` | 待修 |
| D8 | 视频加载时没有封面，只有转圈 | `UI/Media/VideoPlayerPage.swift:85-90`；Kotlin `VideoPlayerPage.kt:183-191` | 待修 |
| D9 | 看图没有 GIF 标 | `ImageViewer.swift:59-63`；Kotlin `ImageViewerPage.kt:123-150` | 待修 |
| D10 | 实况照片点重试不换新地址（Kotlin `refresh = true`） | `ImageViewer.swift:157`；Kotlin `LivePhoto.kt:248` | 已修 |
| D11 | 实况照片的动态是固定居中的一层，不跟缩放；Kotlin 开始播放时把缩放复原 | `ImageViewer.swift:121-126`；Kotlin `ImageViewerPage.kt:176-178` | 待修 |
| D12 | 图片加载失败只能点小图标重试，Kotlin 整块可点 | `UI/Widget/WeiboImage.swift:48-53`；Kotlin `WeiboImage.kt:136` | 待修 |
| D13 | 链接前的图标点不了（画在链接外面），Kotlin 点图标也打开链接 | `UI/Widget/Text/StatusText.swift:126`；Kotlin `StatusText.kt:97` | 待修 |
| D14 | 未登录也显示搜索框，提交后用没有会话的状态发搜索请求。Kotlin 登录后才显示 | `UI/Search/SearchPage.swift:54-57`；Kotlin `SearchPage.kt:134-136` | 待修 |
| D15 | 再点「搜索」页签刷新时不防重复、失败没提示 | `SearchPage.swift:89-95`；Kotlin `SearchPage.kt:217-233` | 待修 |
| D16 | 字体大小页的示例 `allowsHitTesting(false)` 连滚动也挡了，大字号或横屏时看不全。Kotlin 的 `inert()` 放过拖动 | `UI/Settings/SettingsPage.swift:105`；Kotlin `TextSizePage.kt:68,103-105` | 待修 |
| D17 | 改缓存上限后「已用」不重新统计 | `SettingsPage.swift:40-47`；Kotlin `SettingsPage.kt:184` | 待修 |
| D18 | 看图铺满宽度的长图阈值是 3 倍屏幕比例，Kotlin 只要比屏幕高就铺满 | `UI/Media/ZoomableImage.swift:84`；Kotlin `ImageViewerPage.kt:182-183` | 待修 |
| D19 | 时间线总是 1000 宽，Kotlin 在 840 以下用 640 | `UI/Timeline/TimelinePage.swift:127`；Kotlin `AdaptiveLayout.kt:62` | 待修 |
| D20 | 放大转场的 id 是 `statusId/picId`，同一条微博出现两次（两条转发同一原微博、详情页下面的时间线）时 id 重复，动画可能从别的缩略图开始或回到别的缩略图 | `StatusCard.swift:292`、`PicGrid.swift:38`、`App/RootView.swift:137` | 待修 |
| D21 | 被取消的请求报成「网络连接失败」；其他意外错误也都是网络错误。Kotlin 取消不算错误，意外错误显示「加载失败」 | `Core/Net/WeiboHTTP.swift:66-67`、`WeiboError.swift:32-34`；Kotlin `WeiboHttp.kt:85-89`、`LoadState.kt:40` | 待修 |
| D22 | JSON 里 ≥ 2^63 的数字用 `Int64(d)` 会崩溃，Kotlin `toLong()` 截断 | `Core/Util/JSON.swift:71`；Kotlin `JsonRead.kt:24` | 待修 |
| D23 | 没有 `pic_ids` 时 `pic_infos` 按 key 字母排序，Kotlin 保持微博给的顺序 | `Data/Model/PicInfo.swift:119`；Kotlin `PicInfo.kt:162` | 待修 |
| D24 | WebKit 里有重名 Cookie 时取到哪个不确定（`allCookies()` 顺序未定义），可能读到旧的 `SUB` | `Core/Session/WebCookies.swift:57-58`；Kotlin `WebCookies.kt:49-55` | 待修 |
| D25 | 宽屏详情页不分左右两栏（IOS.md §3 已知，Kotlin `ReadingPanes` 没移植） | — | 不修（已知差异） |

## E. 工程和验证

| 编号 | 问题 | 状态 |
|---|---|---|
| E1 | 关于页的声明和 README 不一致（**两个平台都是**）：隐私第 4 条缺「请求频率有上限。遇到验证码时，由你本人在微博的页面里完成。」，免责第 2、4 条措辞不同。CLAUDE.md 要求两者一致 | 待修 |
| E2 | 2 个编译警告：`Task` 已经强持有 `self`，里面的 `[weak self]` 没有作用（`LivePhotoPlayer.swift:88`、`VideoPlayerPage.swift:39`） | 已修 |
| E3 | IOS.md 里写的是 Xcode 27.1，2026-11-04 已更新到 27.2 | 已改（随本文件提交） |
| E4 | 测试：iOS 52 个，Android 约 373 个；iOS 没有页面测试 | 待定 |
| E5 | CI 不跑 iOS，`release.yml` 不出 IPA，分发方式没定（IOS.md §6） | 待用户决定 |
| E6 | IOS.md §5「还没验证」：写操作、真实列表上的滚动翻页、实况照片、视频地址过期换新、`SUB` 自然过期的续期、验证码、iPad 和横屏、最大字体 | 待验证 |
