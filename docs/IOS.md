# 叠澜 · Tidemeld iOS 版（SwiftUI）

写于 2026-10-30。用户要求在 Android 版之外做一个原生 iOS 版：用 SwiftUI，能用系统控件的就用系统控件，按钮和导航栏用系统的液态玻璃（Liquid Glass），深浅色用 voytty iOS 版的整套配色，不做预测性返回（iOS 用系统自带的右滑返回）。这推翻了 PLAN §10 里 2026-10-22「不再支持 iOS」的决定；分发方式还没定（见 §6）。

功能和交互以 Kotlin 版为准，逐页照着翻译；合规边界（PLAN §2）、接口形态（PLAN §5、§8）和 CLAUDE.md 的硬性约束全部照旧。

## 1. 工程

- 目录 `ios/`，工程由 xcodegen 从 `ios/project.yml` 生成（`Tidemeld.xcodeproj` 已 gitignore）。Xcode 27.2（2026-11-04 从 27.1 更新），Swift 6 语言模式（完整并发检查），部署目标 iOS 26.0（液态玻璃、SwiftUI 的 `WebView`/`WebPage` 都要 26）。
- 正式包名 `io.github.leonfox28.tidemeld`（2026-11-05 按用户要求重建商店记录）；调试版仍为 `io.github.leonfox28.maxbo.debug`（名称「叠澜 Debug」），保留开发设备上的真实登录态。正式新标识不继承旧正式安装的数据容器。版本号 `MARKETING_VERSION` 跟 `app/build.gradle.kts` 的 `versionName` 一致，改版本时两处一起改。
- **只用 Apple 自带的框架**，没有第三方依赖：网络 URLSession，网页 WebKit（SwiftUI 的 `WebView` + `WebPage`），视频 AVKit，选图 PhotosUI，图片解码 ImageIO，登录态 Keychain，设置 UserDefaults。开源许可页因此只列 tidemeld 自己的 GPL-3.0（`LICENSE` 打包进应用）。
- 图标与 Android 版是同一个手写的 M，由 `tools/render-icons.swift` 画成 1024 px 的满幅方图（`Resources/Assets.xcassets/AppIcon.appiconset/`），圆角由系统加。配色照 voytty 的 iOS 图标：浅色 `AppIcon.png` 米白底豆沙红，深色 `AppIconDark.png` 是 `#191613` 底 `#C69891`，着色 `AppIconTinted.png` 是灰度图（见 PLAN §11「应用图标」）。

```sh
cd ios && xcodegen generate
xcodebuild -project Tidemeld.xcodeproj -scheme Tidemeld -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd build
xcodebuild test -project Tidemeld.xcodeproj -scheme Tidemeld -destination 'id=<没有真实登录的模拟器>' -derivedDataPath build/dd -collect-test-diagnostics never
xcrun simctl install <模拟器> build/dd/Build/Products/Debug-iphonesimulator/Tidemeld.app   # 覆盖安装，数据保留
xcrun simctl launch <模拟器> io.github.leonfox28.maxbo.debug -tidemeld-open first/status
```

`-collect-test-diagnostics never`：不加的话，测试一失败 xcodebuild 就跑 `simctl diagnose` 收集诊断，最长 10 分钟，看起来像卡住了。

## 2. 代码结构

源码在 `ios/Tidemeld/`，分层和 Android 版对应（括号里是对应的 Kotlin 文件或库）：

- `App/`：`TidemeldApp`（入口）、`AppGraph`（手写的依赖容器，经 `@Environment(AppGraph.self)` 取用；路由 `Router` 和提示 `Toasts` 也在里面，应用只有一个窗口）、`RootView`（`TabView` 四个页签、各页签自己的 `NavigationStack`、整个应用上方的弹层和全屏页、主题和字体大小、未读检查）、`DebugLaunch`（见 §5）。
- `Core/Net/`：`WeiboHTTP`（OkHttp 的拦截器 → 每一跳由 `HopHeaders` 重新放 Cookie、Referer、XSRF 等请求头，重定向的 `Set-Cookie` 也存下）、`WeiboCookieJar`、`WeiboError`（`WeiboException.kt` 的几种异常合成一个 enum，`unwrapResponse` 照搬）、`RequestThrottle`（actor，并发 2、间隔 500 ms、432/418/429 退避）。URLSession 关掉了自己的 Cookie 和缓存。
- `Core/Session/`：`SessionController`、`WebCookies`（`WKHTTPCookieStore`，读得到 HttpOnly 的 `SUB`）、`SessionRenewer`（不挂到界面上的 `WebPage` 打开 weibo.com；每次 `isLoading` 变回 false 就读一次 Cookie，等于 Android 的 `onPageFinished`/`onReceivedError`）、`SessionStorage`（Keychain，`AfterFirstUnlockThisDeviceOnly`，不进备份）。
- `Core/Media/`：`ImageLoader`（代替 Coil：带 Referer、http 改 https、缓存 key 去掉签名参数；磁盘缓存是自己管的 `URLCache`，上限跟设置走；ImageIO 按显示尺寸降采样，GIF 解成动图）、`VideoSource`（选地址、判断过期、重新请求 `statuses/show`）、`VideoAsset`（公开的 `AVAssetResourceLoader` + `URLSession` 加载 MP4/MOV，带 Referer 和浏览器 UA；流式提供所需字节，支持 Range、重定向和取消；播放器持有它，保证弱引用的 loader delegate 不提前释放）。
- `Core/Util/`：`JSON`（容错读取，代替 kotlinx-serialization 的 `JsonElement` 树；`JSONSerialization` 读出的布尔值和数字分开，ID 读成字符串）、`HTML`（代替 jsoup 的小解析器，只认微博正文那几种写法：不带引号的属性、没闭合的标签、字符实体）、`Format`（时间、计数、`devLog`）。
- `Data/`：`WeiboAPI`（端点、续期后读请求重发一次、写请求不重发）和各个模型，解析逻辑逐行照 Kotlin 版。
- `UI/`：按功能分目录，名字和 Android 的 `ui/` 对应。

## 3. 和 Android 版不同的地方

都是为了用系统控件，或者 iOS 上没有对应的东西：

- **导航**：系统的 `TabView`（iOS 26 的玻璃页签栏），搜索是 `role: .search` 的页签加 `.searchable`。每个页签一个 `NavigationStack`，页面是 `Route`（`Router.swift`）。再点一次当前页签：系统会先回到页签的根页面；已在根页面时，`Router.selection` 记一次 reselect，首页、热搜和通知（只有正在显示的那个列表响应）据此回到顶部，已在顶部就刷新。首页和通知的这次刷新照下拉刷新显示（2026-10-30 用户要求，Android 版本来就显示下拉刷新的圈）：SwiftUI 没有从代码开始 `.refreshable` 的接口，`PullToRefresh.swift` 找到列表底下的 UIKit 滚动视图（几个列表并排时取锚点所在位置的那个），先 `beginRefreshing()`、触发 `.refreshable`，再把内容往下移出转圈的位置，圈在 0.25 秒里淡入，免得一下子出现在最终位置、压在还没移下来的第一行上。原先是先移内容、约 0.3 秒后再开始转圈，但内容在开始刷新前已经越过顶部，列表下一次布局时 UIKit 的 `_adjustContentOffsetIfNecessary` 会把它拉回去（通知页滚动时页面会重绘，所以必现），已改掉。刷新结束后内容一般由 UIKit 自己移回去，但列表上一次拖动如果是手指停住再抬起（没有甩），`UIScrollView` 内部的拖动标记（`_scrollViewFlags.dragging`，不是公开的 `isDragging`）会一直留着，直到下一次手指按下或减速结束；点页签碰不到列表，UIKit 就当手指还按着，不把内容移回去，刷新控件停在收回的状态（`_refreshControlState` 4），下一次再点就看不到圈（2026-11-03 查明，首页和通知页都有）。所以 `begin()` 等刷新结束后看一眼：内容 50 ms 里没动、还在顶部以上、手指也没按着，就自己把内容移回顶部，刷新控件随之回到闲置。手动下拉不受影响：松手时内容总要弹回到转圈的位置，这次减速会清掉标记。列表顶上原来有一条线（第一行所在分组的上分隔线），平时贴着顶栏、像是顶栏的下边，下拉时却跟着内容下移，圈就像转在顶栏里（用户发现）；`statusRow()` 把它藏了，圈落在顶栏和内容之间。热搜页没有这样做：它是大标题加搜索框，从代码移动内容会把大标题拉下来压在搜索框上，结束后搜索框还收起了，所以仍旧直接刷新、不显示转圈。
- **页签栏随滚动隐藏**：内容往下滚时整个页签栏隐藏、往回滚时出现，回到顶部总是显示；换到别的页签、或从上面的页面返回时也会出现（Android 选页签时同样）；页面离开屏幕时也把状态放回显示，否则栈里下面那页的 `.hidden` 会让推上来的页面也没有页签栏。页签栏上方的每个滚动页面都套 `tabBarHidesOnScroll()`（`HideOnScroll.swift`，网页用 `web: true`），**新加的页面也要套上**；通知页的四个列表并排，由页面持有一份状态，只有正在显示的那个列表改它。显示时用 `.automatic` 而不是 `.visible`：栈里下面那页的 `.visible` 会盖过上面那页的 `.hidden`。没用系统的收起（`tabBarMinimizeBehavior(.onScrollDown)`，缩成两颗按钮）：系统收起后只在回到顶部、拉过末尾或点按钮时展开，往回滚不展开（2026-10-30 用户发现，UI 测试复现）；临时改收起方式能让它展开，但 UIKit 是一帧跳过去的，`withAnimation`、`UIView.animate` 都没用，也没有公开接口（`toolbarMinimizationRestoration` 和 iOS 27 的 `UIBarMinimization` 只管导航栏）。用户看了说动画不对，选了整个隐藏。出现是系统的淡入（约 0.15 秒，时长由系统定，`withAnimation` 改不了），玻璃和按钮一起淡入；系统的隐藏却是一帧去掉按钮、再淡出空的玻璃，用户觉得不如出现自然，所以隐藏前先由 `TabBarFade` 经 UIKit 把整个页签栏的 alpha 在 0.2 秒里淡到 0，再交给系统隐藏。系统出现时会把 alpha 从当前值淡到 1，**淡出后不要自己把 alpha 改回去**，否则按钮会一下子出现；只有淡出途中往回滚（栏还没隐藏）才自己淡回来，另外出现后 0.5 秒再检查一次，免得栏显示着却是透明的。
- **滚动翻页**：Kotlin 只在滚动位置变化、离末尾不到 800dp 时加载下一页，短得滚不动的列表等用户点「加载更多」。iOS 的页脚在用户往末尾方向滚动时出现、或用户往末尾方向滚动而它在视野里时才加载（`LoadState.swift` 的 `loadsMoreAsScrolled()`，**新加的分页列表也要套上**，不套就只有按钮）。方向只看偏移：`onScrollPhaseChange` 在 `List` 上拖动时一直报 idle，用不了（2026-11-04 UI 测试发现）。原先页脚在 `.onAppear` 里直接加载，第一页不满一屏时不用滑动就请求了第 2 页。
- **弹层**：登录、发微博、转发、写评论都是系统 sheet（评论和转发是半屏 `presentationDetents`），确认删除用 `confirmationDialog`，退出登录用 `alert`。看图和视频是全屏页，看图从缩略图放大进入（`navigationTransition(.zoom)`），可以下滑关闭。
- **提示条**：iOS 没有 snackbar，`Toasts` 在页签栏上方显示一个玻璃胶囊，几秒后自己消失；验证码错误带「去验证」。
- **详情页**：转发和评论用分段控件切换，排序是旁边的菜单，作为列表的分组头吸顶；写评论、转发、赞在系统底部工具栏里，编成一组（一个玻璃胶囊），前面放弹性空白让它靠右；内容往下滚时工具栏收起、往回滚时出现，回到顶部总是显示（`HideOnScroll.swift`，2026-10-30 用户要求）。滚动位置算到内容末尾为止（`ScrollGeometry.offsetFromTop`），拉过末尾弹回不算往回滚；栏出现或隐藏会改变内容上下的留白（工具栏 3pt，页签栏 49pt）、把内容推开，这样的移动也不算，否则栏会在末尾来回闪。楼中楼页的底部工具栏靠右只有一个回复按钮，行为相同。这两页隐藏页签栏。用户问过位置是否合 iOS 的设计建议：人机界面指南里没有 Android 那种浮动按钮，当前页面的操作放在底部工具栏、相关的编成一组，位置交给系统（和页签栏同高，贴着底部指示条），所以用的是系统工具栏而不是自己画的浮动按钮。删除自己的评论在长按菜单里（菜单里还有回复、复制）。
- **通知页**：四个分类是一排文字页签（选中的用强调色加粗、下面一条短线，滑动时跟着移；有未读的带红点），放在导航栏里、代替「通知」这个标题（页签栏已经写着通知），左右滑动切换。原来是一排玻璃按钮，用 `safeAreaBar` 放在导航栏下面，顶栏显得很高；2026-10-30 用户要求顶栏和首页一样高，又要求分类做成普通的页签而不是按钮。系统的分段控件放不了红点，所以没用。页签铺满顶栏（页面宽度减去两边 16pt，最宽 400，导航栏的 principal 位置不给宽度就只给刚好的大小），文字之间的空隙均分，每个页签左右各多 12pt 可点、至少 44pt；四等分不行，两个长标签会几乎贴在一起。翻页是横向的分页 `ScrollView`，页面以过半为准（`scrollPosition` 的 anchor 设成中间，和 Android 的 `pager.currentPage` 一样），不是 `TabView` 的翻页样式：那个底下是 UIKit 的 collection view，把页面摆在上下两条栏之间，满屏高的列表就以这一段为中心摆放，整体往下错开（上下栏高度差的一半，标题栏下面多出 16pt 的空），露在页面外的那部分也点不到（页签栏隐藏后最下面一截滑不动）。列表要像别的页面那样滚到玻璃下面，所以 `GeometryReader` 忽略上下的安全区、每页给满屏大小，量出栏占的高度，再由各列表用 `safeAreaPadding` 留出来。列表自己的滚动边缘效果在这里显示不出来，导航栏只认外面这个横向的 `ScrollView`；它的内容总在顶栏下面，边缘效果一直开着会把第一行的上半截淡掉，所以只在正在显示的列表离开顶部后才打开（`.soft`，默认样式在这里是带分隔线的那种）。**只有正在显示的那个列表会加载**：加载就等于在微博那边标为已读，四页是同时建好的。
- **字体大小**：在系统的动态字体（Dynamic Type）上加减两档，而不是乘一个倍数；所有文字都用文本样式，弹层和菜单是 SwiftUI 的，会跟着变（系统 alert 不跟）。
- **正文**：链接用 `AttributedString` 的 link 加 `OpenURLAction` 拦截；表情先下载、按文字大小缩好，用 `Text(Image)` 插在文字中间（SwiftUI 的 `Text` 不认 `NSTextAttachment`）；`Text` 的 `+` 在 iOS 26 已废弃，改用插值拼接。
- **登录页**：SwiftUI 的 `WebView`。浏览器 UA 和 Android 一样是桌面 Chrome，但要把 `preferredContentMode` 设成 `.mobile`，否则 passport 按桌面布局排成两栏、右边被截掉。http 的页面由 WebKit 升级成 https（`preferredHTTPSNavigationPolicy`），不认识的协议（`sinaweibo://`）一律拦下。
- **退出登录**：清 WebKit 的 Cookie（`WKWebsiteDataStore.removeData`）。**Keychain 在卸载应用后还在**，所以第一次启动时（UserDefaults 里没有 `installed` 标记）先清掉旧的登录态，免得重装后用上一次的会话。
- **宽屏**：时间线卡片在宽度 ≥ 840 时把媒体放到正文右侧（自定义 `Layout`，和 Android 的 `CardLayout` 同一套尺寸），各页正文限宽 640、首页 1000。**详情页在宽屏上不分左右两栏**，Android 的 `ReadingPanes` 没有移植。
- **视频**：系统的 `AVPlayerViewController`（自带控件、画中画）。2026-11-04 核实[苹果官方回复](https://developer.apple.com/forums/thread/671139)后移除了不受支持的 HTTP 请求头选项，改用 `VideoAsset` 的公开资源加载接口；按 SDK 要求关闭 `automaticallyWaitsToMinimizeStalling`，避免自定义加载时起播或恢复等待过久。AirPlay 接收端不能使用应用内的资源加载器（[苹果说明](https://developer.apple.com/forums/thread/83560)），因此关闭外部视频播放，不再宣称支持 AirPlay 视频投放。有声音的播放（视频、点开的实况照片）用 `.playback` 音频类别：静音键打开也有声音，播放时其他应用的声音暂停，关掉后恢复；画中画还要 `Info.plist` 里的后台音频（`ios/Tidemeld/Info.plist`，和 `project.yml` 里的 `INFOPLIST_KEY_*` 合并）。实况照片自己动的时候没声音，用 `.ambient`，不打断其他应用。退到后台时系统会暂停连着画面的播放器（和 Android 退到后台暂停一样），除非开着画中画。Android 版不申请音频焦点，和音乐一起放；iOS 照系统的习惯。实况照片用一个 `AVPlayer` 叠在静图上播放，行为同 Android（点「实况」或长按，带声音；设置打开后停在一张上时静音自动播一次）。

## 4. 测试

`ios/TidemeldTests/`，Swift Testing，只用手写的合成数据：正文解析（照搬 Android `StatusTextParserTest` 的用例）、模型解析、错误映射、Cookie 存取、查询和表单的编码、`$CONFIG` 提取、上传结果、缓存 key、视频地址、格式化、分页列表，以及换账号、请求排队时的 Cookie、图片下载的取消、GIF 的内存、看图的长图、转发。`Support.swift` 里有假的会话存储、网页 Cookie、续期，`testGraph()` 拼出一个 `AppGraph`（已登录，uid 7，不传 `configuration` 时请求一律按离线失败），`FakeWeibo` 是 URL 加载层的假微博（全局一个，用到它的测试放在 `FakeWeiboTests` 下面串行跑）。页面测试还没有，页面都是在模拟器上逐个看过的（§5）。

`ios/TidemeldUITests/` 不是测试而是工具：`ScrollBarsUITests` 打开一页，往下滑、往回滑一点、再往下、再快速往回甩，每步截一张图，用来看页签栏和底部工具栏怎么跟着滚动；另一个方法在关于页滑到页签栏隐藏后打开开源许可再返回，看两页的页签栏。动画要看录屏（`xcrun simctl io <UDID> recordVideo`），再用 ffmpeg 按 60 帧拼图逐帧看。scheme 是 `TidemeldUI`，**只在没有真实账号的 `Tidemeld regression` 上跑**：

```sh
TEST_RUNNER_TIDEMELD_SHOTS=<截图目录> TEST_RUNNER_TIDEMELD_PAGE=<-tidemeld-open 的路径，默认 licenses> \
  xcodebuild test -project Tidemeld.xcodeproj -scheme TidemeldUI -destination 'id=4041A259-B0C0-40B3-81DA-B9258F6474F6' -derivedDataPath build/dd -collect-test-diagnostics never
```

视频加载回归在 `VideoAssetTests.swift`：本地生成的合成 MP4/MOV 验证加载和定位、Referer/UA/Range 与签名 URL 保留、200 忽略 Range、403、截断响应、释放播放器资源时取消请求，以及 206 总长度和 MOV 类型识别。另用本地 HTTP 服务验证过跨主机 302 后请求头和 Range 保留；真实 CDN、真机画中画仍需验证。

## 5. 模拟器与验收

- **`Tidemeld iPhone`**（iPhone 18 Pro，iOS 27.0，UDID `7EB56B5A-6B0D-470C-B479-5BA60B102864`）：2026-10-30 用户在上面登录了测试账号。**只能用 `simctl install` 覆盖安装**（数据保留），不要卸载、抹掉（`simctl erase`）或在上面跑测试。登录态在它的 Keychain 和 WebKit Cookie 里。
- **`Tidemeld test`**（`7D96F02A-891D-4A38-B4E5-850A081A04B8`）：2026-11-05 用户已在此登录真实 X 账号；与 `Tidemeld iPhone` 一样保护，只能覆盖安装，不得卸载、清数据或跑自动化测试。下方此前在该设备运行测试的记录均为登录之前的历史记录。
- **`Tidemeld regression`**（`4041A259-B0C0-40B3-81DA-B9258F6474F6`，iPhone 18 Pro / iOS 27.0）：2026-11-05 新建，无真实账号，后续单元测试、UI 测试及未登录界面检查用此设备。不要登录真实账号。本机其他模拟器属于 voytty，不要用。
- 本机模拟器由 Device Hub（`com.apple.dt.Devices`）承载。交互可经 CUA 执行，列表的辅助功能 `Scroll Down` / `Scroll Up` 动作可用于滚动；真实登录设备只做用户授权的界面检查。自动化回归仍只在 `Tidemeld regression` 上运行（§4）。
- 调试版的启动参数 `-tidemeld-open <路径>` 直接打开页面：`login`、`compose`、`settings`、`about`、`licenses`、`tab/<search|notifications|me>`、`reselect/<home|search|notifications>`（打开页签约 4 秒后再点一次）、`status/<id>`、`u/<uid>`、`n/<昵称>`、`results/<词>`（中文和 `#` 要 URL 编码）、`web/<网址>`（应用内浏览器），时间线加载后的 `first/<status|user|pic|live|video|thread>`，以及诊断页的 `diag/<reads|renewal>`。
- **2026-10-30 在 `Tidemeld iPhone` 的真实会话上看过**：登录（官方页面，登录后自动关闭）、首页时间线（表情、链接图标、转发框、九宫格、认证、来源和地区；浅色和深色）、详情页（转发/评论切换、排序、评论、底部工具栏）、楼中楼、看图（翻页、页码）、视频播放、用户主页（封面、关注关系、置顶、展开）、通知（评论列表、带图评论、原微博引用）、热搜（置顶、前三名配色、标签、热度）、话题搜索结果（话题头和计数）、发微博弹层、诊断页「核对接口」全部正常、「模拟登录过期」3.4 秒续期成功（网页里的会话仍有效的那条路径）。
- **2026-10-30 在 `Tidemeld test` 上用 UI 测试滑过**：开源许可（`ScrollView`）和关于（`List`）两页的页签栏往下滚隐藏、往回滚一点就出现、再往下又隐藏，关于页拉到末尾不闪，录屏逐帧看过出现和隐藏都是玻璃和按钮一起淡入淡出；隐藏后打开新页面、返回都有页签栏；给关于页临时加上详情页那样的底部工具栏，收起和出现也对，拉过末尾不再闪。
- **2026-10-30 在 `Tidemeld iPhone` 上用 `reselect/home` 录屏逐帧看过**：首页在顶部时再点一次，内容平滑下移、圈在空出来的地方转，刷新完弹回，圈不压在内容上。
- **2026-10-30 在 `Tidemeld iPhone` 上用 `reselect/notifications` 看过**：真实的通知列表在顶部时再点一次，内容下移、圈在页签和第一条之间转、刷新完弹回；不在顶部时点 tab 回到顶部（`Tidemeld test` 上的合成列表，第四页「赞」也对，只有正在显示的列表响应）。真实点 tab 时系统自己不会滚动列表。
- **2026-11-03 在 `Tidemeld test` 上用 UI 测试录屏逐帧看过**：通知页和首页（临时换成合成的行）慢慢往下拖两次、往回拖一点，点页签回到顶部，再连点两次刷新：每次都有圈，刷新完内容弹回；改之前两页都是内容停在下移的位置、第二次没有圈。刚启动时在顶部点、手动下拉都照旧（UIKit 自己移回，不用补）。
- **要登录才有内容的列表怎么在无真实账号的 `Tidemeld regression` 上测**：临时改页面，未登录也显示列表，`List` 换成 40 行合成的行（`ForEach((0..<40).map { "r\($0)" }, id: \.self)`，回顶部的 id 用 `"r0"`），去掉开始加载的 `.task`，刷新里的请求换成 `Task.sleep(for: .seconds(1.5))`；再临时加一个 UI 测试：启动 `tab/<页签>`，拖动后点 `app.tabBars.buttons["通知"]`（或「首页」），配合录屏看。XCUITest 的 `tap()` 会等应用空闲，紧跟在点按后面的截图时间不准，动画要看录屏。要看 UIKit 的内部状态，可以临时用 `class_copyIvarList` 读刷新控件的 `_refreshControlState`（0 闲置、3 刷新中、4 收回中）和滚动视图 `_scrollViewFlags` 的各个位（类型编码里带字段名）。这些临时改动都不要提交。
- **2026-10-30 通知页**：在 `Tidemeld iPhone` 上看过顶栏和首页一样高、第一条和首页对齐、顶部不淡；在 `Tidemeld test` 上临时把列表换成合成的行（不发请求、不看登录态）跑 UI 测试，点页签切换、左右滑动换页、慢慢拖不到一半留在原页、往下滚页签栏隐藏且原来页签栏那一截能拖、滚到顶栏下面有模糊、回到顶部模糊消失，都对。真实列表的滑动没看过（要登录）。
- **还没验证**：详情页和楼中楼真实页面上的底部工具栏随滚动收起和出现（要登录，只在关于页上模拟过）、要登录的列表页（首页、通知、热搜、用户主页、搜索结果）和网页里页签栏的隐藏和出现、换页签和返回时页签栏重新出现、真实列表上真的点页签时的再点一次和不在顶部时回到顶部（启动参数只模拟了 `Router.selection` 的设置；首页和通知页的合成列表上 UI 测试真的点过，见上）、从缩略图放大进入看图和下滑关闭（启动参数打开的看图没有缩略图）、写操作（点赞、评论、回复、删除、转发、发微博，按约定要用户同意并用指定的测试微博）、滚动翻页（要登录才有内容可滑，只看了代码路径）、实况照片（那一页时间线里没有）、视频地址过期后换新、真正的 `SUB` 自然过期（要用 `ALC` 换新的那条续期路径）、验证码、iPad 和横屏、字体大小调到最大时的排版。2026-11-04 按审查（[IOS_REVIEW.md](IOS_REVIEW.md)）修的，只编译过或只在 `Tidemeld test` 上看过的：静音键打开时视频有声音、画中画（A7，要真机）；打开带红点的通知页签后列表刷新（A1）；换账号后通知和各页签重新开始（A9、A10，有单元测试）；登录失败时登录页上的提示（A8）；选图后读入时「发送」等着（A5）、上传进度、发微博时「去验证」盖在弹层上（D3）、转发时光标在最前（D2）；视频加载时的封面（D8）；看图里长图能左右翻（A4，有单元测试）、GIF 标（D9）；真实列表上滚到末尾才翻页（B1，合成列表上 UI 测试滑过）；宽屏中等宽度的时间线（D19）。

## 6. 还没定的

2026-11-04 的审查结果（bug、和 Android 的差异、修复进度）在 [IOS_REVIEW.md](IOS_REVIEW.md)。

- **分发**：2026-11-05 用户决定准备 App Store 美区首发，免费、界面保留中文，使用当前 Mac 的付费开发者账号。此前“基本上不了架”的判断过于绝对，已撤回；第三方微博客户端有上架先例，但仍需满足第三方服务使用许可、内容安全和隐私披露等要求。当前准备状态、资料与未完成项见 [APP_STORE.md](APP_STORE.md)。
- **CI**：`ci.yml` 还只跑 Android；iOS 的构建和测试要 macOS runner。

## 7. 多账号与聚合（2026-11-05，v0.14.0 开发版）

`AccountManager` 在独立的 Keychain 项目保存平台、账号和 Cookie，迁移旧微博登录。`SocialFeedController` 为每个账号维护游标与错误，按时间合并去重。首页菜单选择聚合、微博或 X；账号管理可分别添加、重新登录、移除同平台多个账号。微博的卡片、导航和弹层携带来源账号上下文；搜索、通知和发微博使用当前微博账号。

X 使用官方网页登录和原生 `XWebAPI`，协议配置与 Android 共用 `protocol/x-web.json`。正文、图片、引用和转发使用原生卡片，后续已接入原生互动以及与微博共用的图片查看器和视频播放器（见下方记录）。iOS 单个真实 X 账号的登录、原生读取和平台筛选已于 2026-11-05 验证；403/429 会显示错误，不绕过安全验证，不自动重试。

本次验证：`Tidemeld test` 上 87 项测试通过，包含多个账号合并、独立游标、失败恢复、网页账号切换、过期状态和切换账号后的迟到响应隔离。已在界面核对聚合/微博/X 菜单、账号管理和平台选择；未操作 `Tidemeld iPhone` 的真实登录态。

用户随后在 `Tidemeld test` 登录 X；已确认账号保存、原生信息流、平台筛选和向下连续浏览正常，未执行写操作。多账号真实混合和请求级分页边界仍待验证。从这次登录起，`Tidemeld test` 的真实凭据必须保留，之后自动化回归使用上文的 `Tidemeld regression`。


### 2026-11-05：X 原生互动

新增 `UI/X`：信息流/详情共享按账号和原帖隔离的互动状态，原生评论详情、回复/引用输入框、点赞与转发及各自取消操作。协议配置与 Android 共用；写操作不自动重试，未知结果提示刷新，失败保留内存草稿。`Tidemeld regression`（无真实账号）94 项测试通过；`Tidemeld test` 仅保留数据覆盖更新，已从 UI 确认真实评论列表、连续浏览及输入框正常。没有实测真实写入，`Tidemeld iPhone` 未在此次验收中更新。


### 2026-11-05：微博与 X 复用展示组件

将微博现有卡片、作者栏、引用框、宽屏布局、互动计数、详情列表与底栏、评论输入及发送状态抽入 `UI/Post/`。`StatusCard` / `XPostCard` 只提供平台内容，`PostInteractionActions` 持有绑定来源账号的操作回调；`PostResponseHeader` 只展示可加载的列表，`PostComposerRequest.attachments` 显式提供可选附件能力。微博的评论图片支持检查/上传留在适配器，X 不提供该能力。接口、凭据与互动状态继续按平台隔离，新增平台应复用这些组件。94 项回归通过，保留登录更新 `Tidemeld test` 后核对了真实卡片、评论详情、底部互动栏与发送弹层。

### 2026-11-05：更新 Tidemeld iPhone 并修复启动崩溃

覆盖更新保存真实微博登录的 `Tidemeld iPhone` 时，发现聚合信息流的异步 provider 丢失主执行器隔离，调用 `AppGraph.forAccount()` 读取账号时触发运行时断言。`SocialFeedController.fetch` 现显式标为 `@MainActor`，由 `AppGraph` 的隔离工厂方法创建。新增回归直接使用生产 provider，覆盖恢复旧微博会话、多账号凭据隔离、加载与刷新；空白 `Tidemeld regression` 的 95 项测试通过。修复后再次保留数据覆盖安装，已从界面确认微博信息流正常加载、账号仍已登录，并打开账号管理供用户添加 X。未执行真实写操作。

### 2026-11-05：过滤 X 广告

用户在 `Tidemeld iPhone` 完成 X 登录后要求不显示标记为广告的条目。`parseXEntries` 现在按已有的 `promotedMetadata` 标记过滤，作用于 X 信息流、聚合中的 X 来源及评论列表；在去重前过滤以保留同 ID 的普通条目，整页均为广告时仍返回分页游标。共享 UI 无需平台判断。96 项合成测试通过，覆盖顶层/模块广告、转发广告、同 ID 普通条目、空页游标和评论广告。保留数据覆盖更新 `Tidemeld iPhone` 后，从界面确认此前首屏广告已消失，普通帖子正常显示；未执行真实写操作。

### 2026-11-05：共用图片与视频播放框架

`Core/Media/MediaPlayback` 定义平台无关的 `VideoRequest`（封面、CDN 请求头、地址刷新回调）和可选 `PhotoMotion`（实况照片能力）。`VideoPlayerPage`、`VideoModel`、`ImageViewer` 和 `LivePhotoPlayer` 不再访问微博 API；`WeiboMedia` / `XMediaPlayback` 适配器负责来源账号、帖子及媒体序号。`MediaVideoAsset` 共用同一个支持 Range/seek/取消的 MP4/MOV 加载器，CDN 不携带账号 Cookie。单视频封面也从微博卡片抽入 `UI/Post/VideoCover`。

X 的媒体解析保留图片/视频混排顺序、尺寸、多个视频及 `animated_gif` 的 MP4，引用帖也保留媒体。图片继续使用同一个缩放/翻页查看器；视频点击直接在应用内播放。刷新地址仍绑定原账号和登录代次，过期失败最多刷新一次。空白回归模拟器 100 项测试通过，包含两个平台的真实 AVFoundation 合成视频解码、播放和跳转，以及关闭时取消解析、原帖/账号/视频序号隔离。保留登录更新 `Tidemeld iPhone` 后，确认真实 X 视频播放、暂停/继续和跳转 10 秒、引用帖图片查看与双击缩放，以及微博图片查看和视频播放正常。Android 同步实现并通过 413 项测试及全量检查；Android 实机播放、真实地址自然过期及 X 仅有非 MP4 流的条目仍待验证。

### 2026-11-05：视频播放页只保留一套顶部控件

移除共用 `VideoPlayerPage` 外层的导航栏与橙色关闭按钮，让 AVKit 占满屏幕并按安全区域摆放系统关闭、静音控件。加载中或失败时才显示备用关闭按钮。模拟器构建通过，并保留登录覆盖更新 `Tidemeld iPhone`；实测 X 视频正常播放、仅有一个关闭按钮、关闭和静音已上移，点击系统关闭可返回信息流。此布局同时用于微博和 X。

### 2026-11-05：首页固定账号入口

首页左侧无论是否登录，都使用原“我”页签的 `person` 图标并打开账号管理；不再显示本人头像，移除为顶栏头像请求资料的任务。构建通过，已覆盖更新 `Tidemeld iPhone` 并核对已登录入口；另在未登录的 `Tidemeld regression` 确认同一图标可直接进入账号管理，显示微博和 X 的添加账号入口。Android 同步使用原“我”页签的 `Icons.Outlined.Person`。

### 2026-11-05：卡片用矢量图标标识平台

移除信息流每张卡片上方的“平台 · 账号”文字行；`PostHeader` 接收平台适配器提供的图标和名称，在右上角统一显示 20pt 矢量标识（32pt 布局区域），并提供“来源：微博 / X”的辅助功能标签。卡片和详情页共用，不增加图标按钮；X 移除“更多选项”及其“在 X 网页中打开”菜单，微博自己的删除操作保留。SVG 来源和跨端生成方式见 [PLATFORM_ICONS.md](PLATFORM_ICONS.md)。iOS 构建通过，已覆盖更新 `Tidemeld iPhone`，在聚合流及 X 流确认两个图标、来源文字移除和 X 菜单移除；随后恢复聚合筛选。Android 同步实现并通过格式、lint、构建和 413 项测试。

同日按用户反馈将两端平台图标从 20pt/dp 缩小到 16pt/dp（宽高各减少 20%），32pt/dp 布局区域和对齐保持不变；尺寸仍由共享 `PostHeader` 统一决定。
