# maxbo iOS 版（SwiftUI）

写于 2026-10-30。用户要求在 Android 版之外做一个原生 iOS 版：用 SwiftUI，能用系统控件的就用系统控件，按钮和导航栏用系统的液态玻璃（Liquid Glass），深浅色用 voytty iOS 版的整套配色，不做预测性返回（iOS 用系统自带的右滑返回）。这推翻了 PLAN §10 里 2026-10-22「不再支持 iOS」的决定；分发方式还没定（见 §6）。

功能和交互以 Kotlin 版为准，逐页照着翻译；合规边界（PLAN §2）、接口形态（PLAN §5、§8）和 CLAUDE.md 的硬性约束全部照旧。

## 1. 工程

- 目录 `ios/`，工程由 xcodegen 从 `ios/project.yml` 生成（`Maxbo.xcodeproj` 已 gitignore）。Xcode 27.1，Swift 6 语言模式（完整并发检查），部署目标 iOS 26.0（液态玻璃、SwiftUI 的 `WebView`/`WebPage` 都要 26）。
- 包名 `io.github.leonfox28.maxbo`，调试版 `io.github.leonfox28.maxbo.debug`（名称「maxbo debug」）。版本号 `MARKETING_VERSION` 跟 `app/build.gradle.kts` 的 `versionName` 一致，改版本时两处一起改。
- **只用 Apple 自带的框架**，没有第三方依赖：网络 URLSession，网页 WebKit（SwiftUI 的 `WebView` + `WebPage`），视频 AVKit，选图 PhotosUI，图片解码 ImageIO，登录态 Keychain，设置 UserDefaults。开源许可页因此只列 maxbo 自己的 GPL-3.0（`LICENSE` 打包进应用）。
- 图标是 Android 的同一个图形（`ic_launcher_foreground.xml` 的两段圆弧，底色 `#3F51B5`），取 108 画布中间的 84 渲染成 1024 px（`Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`）。

```sh
cd ios && xcodegen generate
xcodebuild -project Maxbo.xcodeproj -scheme Maxbo -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd build
xcodebuild test -project Maxbo.xcodeproj -scheme Maxbo -destination 'id=<没有真实登录的模拟器>' -derivedDataPath build/dd -collect-test-diagnostics never
xcrun simctl install <模拟器> build/dd/Build/Products/Debug-iphonesimulator/Maxbo.app   # 覆盖安装，数据保留
xcrun simctl launch <模拟器> io.github.leonfox28.maxbo.debug -maxbo-open first/status
```

`-collect-test-diagnostics never`：不加的话，测试一失败 xcodebuild 就跑 `simctl diagnose` 收集诊断，最长 10 分钟，看起来像卡住了。

## 2. 代码结构

源码在 `ios/Maxbo/`，分层和 Android 版对应（括号里是对应的 Kotlin 文件或库）：

- `App/`：`MaxboApp`（入口）、`AppGraph`（手写的依赖容器，经 `@Environment(AppGraph.self)` 取用；路由 `Router` 和提示 `Toasts` 也在里面，应用只有一个窗口）、`RootView`（`TabView` 四个页签、各页签自己的 `NavigationStack`、整个应用上方的弹层和全屏页、主题和字体大小、未读检查）、`DebugLaunch`（见 §5）。
- `Core/Net/`：`WeiboHTTP`（OkHttp 的拦截器 → 每一跳由 `HopHeaders` 重新放 Cookie、Referer、XSRF 等请求头，重定向的 `Set-Cookie` 也存下）、`WeiboCookieJar`、`WeiboError`（`WeiboException.kt` 的几种异常合成一个 enum，`unwrapResponse` 照搬）、`RequestThrottle`（actor，并发 2、间隔 500 ms、432/418/429 退避）。URLSession 关掉了自己的 Cookie 和缓存。
- `Core/Session/`：`SessionController`、`WebCookies`（`WKHTTPCookieStore`，读得到 HttpOnly 的 `SUB`）、`SessionRenewer`（不挂到界面上的 `WebPage` 打开 weibo.com；每次 `isLoading` 变回 false 就读一次 Cookie，等于 Android 的 `onPageFinished`/`onReceivedError`）、`SessionStorage`（Keychain，`AfterFirstUnlockThisDeviceOnly`，不进备份）。
- `Core/Media/`：`ImageLoader`（代替 Coil：带 Referer、http 改 https、缓存 key 去掉签名参数；磁盘缓存是自己管的 `URLCache`，上限跟设置走；ImageIO 按显示尺寸降采样，GIF 解成动图）、`VideoSource`（选地址、判断过期、重新请求 `statuses/show`；AVFoundation 用 `AVURLAssetHTTPHeaderFieldsKey` 带 Referer，这个键没有公开的名字）。
- `Core/Util/`：`JSON`（容错读取，代替 kotlinx-serialization 的 `JsonElement` 树；`JSONSerialization` 读出的布尔值和数字分开，ID 读成字符串）、`HTML`（代替 jsoup 的小解析器，只认微博正文那几种写法：不带引号的属性、没闭合的标签、字符实体）、`Format`（时间、计数、`devLog`）。
- `Data/`：`WeiboAPI`（端点、续期后读请求重发一次、写请求不重发）和各个模型，解析逻辑逐行照 Kotlin 版。
- `UI/`：按功能分目录，名字和 Android 的 `ui/` 对应。

## 3. 和 Android 版不同的地方

都是为了用系统控件，或者 iOS 上没有对应的东西：

- **导航**：系统的 `TabView`（iOS 26 的玻璃页签栏），搜索是 `role: .search` 的页签加 `.searchable`。每个页签一个 `NavigationStack`，页面是 `Route`（`Router.swift`）。再点一次当前页签：系统会先回到页签的根页面；已在根页面时，`Router.selection` 记一次 reselect，首页、热搜和通知（只有正在显示的那个列表响应）据此回到顶部，已在顶部就刷新。首页和通知的这次刷新照下拉刷新显示（2026-10-30 用户要求，Android 版本来就显示下拉刷新的圈）：SwiftUI 没有从代码开始 `.refreshable` 的接口，`PullToRefresh.swift` 找到列表底下的 UIKit 滚动视图（几个列表并排时取锚点所在位置的那个），先 `beginRefreshing()`、触发 `.refreshable`，再把内容往下移出转圈的位置，圈在 0.25 秒里淡入，免得一下子出现在最终位置、压在还没移下来的第一行上。原先是先移内容、约 0.3 秒后再开始转圈，但内容在开始刷新前已经越过顶部，列表下一次布局时 UIKit 的 `_adjustContentOffsetIfNecessary` 会把它拉回去（通知页滚动时页面会重绘，所以必现），已改掉。刷新结束后内容一般由 UIKit 自己移回去，但列表上一次拖动如果是手指停住再抬起（没有甩），`UIScrollView` 内部的拖动标记（`_scrollViewFlags.dragging`，不是公开的 `isDragging`）会一直留着，直到下一次手指按下或减速结束；点页签碰不到列表，UIKit 就当手指还按着，不把内容移回去，刷新控件停在收回的状态（`_refreshControlState` 4），下一次再点就看不到圈（2026-11-03 查明，首页和通知页都有）。所以 `begin()` 等刷新结束后看一眼：内容 50 ms 里没动、还在顶部以上、手指也没按着，就自己把内容移回顶部，刷新控件随之回到闲置。手动下拉不受影响：松手时内容总要弹回到转圈的位置，这次减速会清掉标记。列表顶上原来有一条线（第一行所在分组的上分隔线），平时贴着顶栏、像是顶栏的下边，下拉时却跟着内容下移，圈就像转在顶栏里（用户发现）；`statusRow()` 把它藏了，圈落在顶栏和内容之间。热搜页没有这样做：它是大标题加搜索框，从代码移动内容会把大标题拉下来压在搜索框上，结束后搜索框还收起了，所以仍旧直接刷新、不显示转圈。
- **页签栏随滚动隐藏**：内容往下滚时整个页签栏隐藏、往回滚时出现，回到顶部总是显示；换到别的页签、或从上面的页面返回时也会出现（Android 选页签时同样）；页面离开屏幕时也把状态放回显示，否则栈里下面那页的 `.hidden` 会让推上来的页面也没有页签栏。页签栏上方的每个滚动页面都套 `tabBarHidesOnScroll()`（`HideOnScroll.swift`，网页用 `web: true`），**新加的页面也要套上**；通知页的四个列表并排，由页面持有一份状态，只有正在显示的那个列表改它。显示时用 `.automatic` 而不是 `.visible`：栈里下面那页的 `.visible` 会盖过上面那页的 `.hidden`。没用系统的收起（`tabBarMinimizeBehavior(.onScrollDown)`，缩成两颗按钮）：系统收起后只在回到顶部、拉过末尾或点按钮时展开，往回滚不展开（2026-10-30 用户发现，UI 测试复现）；临时改收起方式能让它展开，但 UIKit 是一帧跳过去的，`withAnimation`、`UIView.animate` 都没用，也没有公开接口（`toolbarMinimizationRestoration` 和 iOS 27 的 `UIBarMinimization` 只管导航栏）。用户看了说动画不对，选了整个隐藏。出现是系统的淡入（约 0.15 秒，时长由系统定，`withAnimation` 改不了），玻璃和按钮一起淡入；系统的隐藏却是一帧去掉按钮、再淡出空的玻璃，用户觉得不如出现自然，所以隐藏前先由 `TabBarFade` 经 UIKit 把整个页签栏的 alpha 在 0.2 秒里淡到 0，再交给系统隐藏。系统出现时会把 alpha 从当前值淡到 1，**淡出后不要自己把 alpha 改回去**，否则按钮会一下子出现；只有淡出途中往回滚（栏还没隐藏）才自己淡回来，另外出现后 0.5 秒再检查一次，免得栏显示着却是透明的。
- **弹层**：登录、发微博、转发、写评论都是系统 sheet（评论和转发是半屏 `presentationDetents`），确认删除用 `confirmationDialog`，退出登录用 `alert`。看图和视频是全屏页，看图从缩略图放大进入（`navigationTransition(.zoom)`），可以下滑关闭。
- **提示条**：iOS 没有 snackbar，`Toasts` 在页签栏上方显示一个玻璃胶囊，几秒后自己消失；验证码错误带「去验证」。
- **详情页**：转发和评论用分段控件切换，排序是旁边的菜单，作为列表的分组头吸顶；写评论、转发、赞在系统底部工具栏里，编成一组（一个玻璃胶囊），前面放弹性空白让它靠右；内容往下滚时工具栏收起、往回滚时出现，回到顶部总是显示（`HideOnScroll.swift`，2026-10-30 用户要求）。滚动位置算到内容末尾为止（`ScrollGeometry.offsetFromTop`），拉过末尾弹回不算往回滚；栏出现或隐藏会改变内容上下的留白（工具栏 3pt，页签栏 49pt）、把内容推开，这样的移动也不算，否则栏会在末尾来回闪。楼中楼页的底部工具栏靠右只有一个回复按钮，行为相同。这两页隐藏页签栏。用户问过位置是否合 iOS 的设计建议：人机界面指南里没有 Android 那种浮动按钮，当前页面的操作放在底部工具栏、相关的编成一组，位置交给系统（和页签栏同高，贴着底部指示条），所以用的是系统工具栏而不是自己画的浮动按钮。删除自己的评论在长按菜单里（菜单里还有回复、复制）。
- **通知页**：四个分类是一排文字页签（选中的用强调色加粗、下面一条短线，滑动时跟着移；有未读的带红点），放在导航栏里、代替「通知」这个标题（页签栏已经写着通知），左右滑动切换。原来是一排玻璃按钮，用 `safeAreaBar` 放在导航栏下面，顶栏显得很高；2026-10-30 用户要求顶栏和首页一样高，又要求分类做成普通的页签而不是按钮。系统的分段控件放不了红点，所以没用。页签铺满顶栏（页面宽度减去两边 16pt，最宽 400，导航栏的 principal 位置不给宽度就只给刚好的大小），文字之间的空隙均分，每个页签左右各多 12pt 可点、至少 44pt；四等分不行，两个长标签会几乎贴在一起。翻页是横向的分页 `ScrollView`，页面以过半为准（`scrollPosition` 的 anchor 设成中间，和 Android 的 `pager.currentPage` 一样），不是 `TabView` 的翻页样式：那个底下是 UIKit 的 collection view，把页面摆在上下两条栏之间，满屏高的列表就以这一段为中心摆放，整体往下错开（上下栏高度差的一半，标题栏下面多出 16pt 的空），露在页面外的那部分也点不到（页签栏隐藏后最下面一截滑不动）。列表要像别的页面那样滚到玻璃下面，所以 `GeometryReader` 忽略上下的安全区、每页给满屏大小，量出栏占的高度，再由各列表用 `safeAreaPadding` 留出来。列表自己的滚动边缘效果在这里显示不出来，导航栏只认外面这个横向的 `ScrollView`；它的内容总在顶栏下面，边缘效果一直开着会把第一行的上半截淡掉，所以只在正在显示的列表离开顶部后才打开（`.soft`，默认样式在这里是带分隔线的那种）。**只有正在显示的那个列表会加载**：加载就等于在微博那边标为已读，四页是同时建好的。
- **字体大小**：在系统的动态字体（Dynamic Type）上加减两档，而不是乘一个倍数；所有文字都用文本样式，弹层和菜单是 SwiftUI 的，会跟着变（系统 alert 不跟）。
- **正文**：链接用 `AttributedString` 的 link 加 `OpenURLAction` 拦截；表情先下载、按文字大小缩好，用 `Text(Image)` 插在文字中间（SwiftUI 的 `Text` 不认 `NSTextAttachment`）；`Text` 的 `+` 在 iOS 26 已废弃，改用插值拼接。
- **登录页**：SwiftUI 的 `WebView`。浏览器 UA 和 Android 一样是桌面 Chrome，但要把 `preferredContentMode` 设成 `.mobile`，否则 passport 按桌面布局排成两栏、右边被截掉。http 的页面由 WebKit 升级成 https（`preferredHTTPSNavigationPolicy`），不认识的协议（`sinaweibo://`）一律拦下。
- **退出登录**：清 WebKit 的 Cookie（`WKWebsiteDataStore.removeData`）。**Keychain 在卸载应用后还在**，所以第一次启动时（UserDefaults 里没有 `installed` 标记）先清掉旧的登录态，免得重装后用上一次的会话。
- **宽屏**：时间线卡片在宽度 ≥ 840 时把媒体放到正文右侧（自定义 `Layout`，和 Android 的 `CardLayout` 同一套尺寸），各页正文限宽 640、首页 1000。**详情页在宽屏上不分左右两栏**，Android 的 `ReadingPanes` 没有移植。
- **视频**：系统的 `AVPlayerViewController`（自带控件、画中画、AirPlay）。实况照片用一个 `AVPlayer` 叠在静图上播放，行为同 Android（点「实况」或长按，带声音；设置打开后停在一张上时静音自动播一次）。

## 4. 测试

`ios/MaxboTests/`，Swift Testing，只用手写的合成数据：正文解析（照搬 Android `StatusTextParserTest` 的用例）、模型解析、错误映射、Cookie 存取、查询和表单的编码、`$CONFIG` 提取、上传结果、缓存 key、视频地址、格式化、分页列表。页面测试还没有，页面都是在模拟器上逐个看过的（§5）。

`ios/MaxboUITests/` 不是测试而是工具：`ScrollBarsUITests` 打开一页，往下滑、往回滑一点、再往下、再快速往回甩，每步截一张图，用来看页签栏和底部工具栏怎么跟着滚动；另一个方法在关于页滑到页签栏隐藏后打开开源许可再返回，看两页的页签栏。动画要看录屏（`xcrun simctl io <UDID> recordVideo`），再用 ffmpeg 按 60 帧拼图逐帧看。scheme 是 `MaxboUI`，**只在 `maxbo test` 上跑**：

```sh
TEST_RUNNER_MAXBO_SHOTS=<截图目录> TEST_RUNNER_MAXBO_PAGE=<-maxbo-open 的路径，默认 licenses> \
  xcodebuild test -project Maxbo.xcodeproj -scheme MaxboUI -destination 'id=<maxbo test>' -derivedDataPath build/dd -collect-test-diagnostics never
```

## 5. 模拟器与验收

- **`maxbo iPhone`**（iPhone 18 Pro，iOS 27.0，UDID `7EB56B5A-6B0D-470C-B479-5BA60B102864`）：2026-10-30 用户在上面登录了测试账号。**只能用 `simctl install` 覆盖安装**（数据保留），不要卸载、抹掉（`simctl erase`）或在上面跑测试。登录态在它的 Keychain 和 WebKit Cookie 里。
- **`maxbo test`**（同型号，没有登录）：跑单元测试、看未登录的页面。本机其他模拟器（iPhone 18 Pro、iPad Pro、iPhone Duo 等）属于 voytty，不要用。
- 本机没有独立的 Simulator.app，模拟器由用户在 Xcode 里打开；截图用 `xcrun simctl io <UDID> screenshot`。点按和滑动只能在 `maxbo test` 上经 UI 测试（§4），所以要登录才有内容的页面滑不了。
- 调试版的启动参数 `-maxbo-open <路径>` 直接打开页面：`login`、`compose`、`settings`、`about`、`licenses`、`tab/<search|notifications|me>`、`reselect/<home|search|notifications>`（打开页签约 4 秒后再点一次）、`status/<id>`、`u/<uid>`、`n/<昵称>`、`results/<词>`（中文和 `#` 要 URL 编码），时间线加载后的 `first/<status|user|pic|live|video|thread>`，以及诊断页的 `diag/<reads|renewal>`。
- **2026-10-30 在 `maxbo iPhone` 的真实会话上看过**：登录（官方页面，登录后自动关闭）、首页时间线（表情、链接图标、转发框、九宫格、认证、来源和地区；浅色和深色）、详情页（转发/评论切换、排序、评论、底部工具栏）、楼中楼、看图（翻页、页码）、视频播放、用户主页（封面、关注关系、置顶、展开）、通知（评论列表、带图评论、原微博引用）、热搜（置顶、前三名配色、标签、热度）、话题搜索结果（话题头和计数）、发微博弹层、诊断页「核对接口」全部正常、「模拟登录过期」3.4 秒续期成功（网页里的会话仍有效的那条路径）。
- **2026-10-30 在 `maxbo test` 上用 UI 测试滑过**：开源许可（`ScrollView`）和关于（`List`）两页的页签栏往下滚隐藏、往回滚一点就出现、再往下又隐藏，关于页拉到末尾不闪，录屏逐帧看过出现和隐藏都是玻璃和按钮一起淡入淡出；隐藏后打开新页面、返回都有页签栏；给关于页临时加上详情页那样的底部工具栏，收起和出现也对，拉过末尾不再闪。
- **2026-10-30 在 `maxbo iPhone` 上用 `reselect/home` 录屏逐帧看过**：首页在顶部时再点一次，内容平滑下移、圈在空出来的地方转，刷新完弹回，圈不压在内容上。
- **2026-10-30 在 `maxbo iPhone` 上用 `reselect/notifications` 看过**：真实的通知列表在顶部时再点一次，内容下移、圈在页签和第一条之间转、刷新完弹回；不在顶部时点 tab 回到顶部（`maxbo test` 上的合成列表，第四页「赞」也对，只有正在显示的列表响应）。真实点 tab 时系统自己不会滚动列表。
- **2026-11-03 在 `maxbo test` 上用 UI 测试录屏逐帧看过**：通知页和首页（临时换成合成的行）慢慢往下拖两次、往回拖一点，点页签回到顶部，再连点两次刷新：每次都有圈，刷新完内容弹回；改之前两页都是内容停在下移的位置、第二次没有圈。刚启动时在顶部点、手动下拉都照旧（UIKit 自己移回，不用补）。
- **要登录才有内容的列表怎么在 `maxbo test` 上测**：临时改页面，未登录也显示列表，`List` 换成 40 行合成的行（`ForEach((0..<40).map { "r\($0)" }, id: \.self)`，回顶部的 id 用 `"r0"`），去掉开始加载的 `.task`，刷新里的请求换成 `Task.sleep(for: .seconds(1.5))`；再临时加一个 UI 测试：启动 `tab/<页签>`，拖动后点 `app.tabBars.buttons["通知"]`（或「首页」），配合录屏看。XCUITest 的 `tap()` 会等应用空闲，紧跟在点按后面的截图时间不准，动画要看录屏。要看 UIKit 的内部状态，可以临时用 `class_copyIvarList` 读刷新控件的 `_refreshControlState`（0 闲置、3 刷新中、4 收回中）和滚动视图 `_scrollViewFlags` 的各个位（类型编码里带字段名）。这些临时改动都不要提交。
- **2026-10-30 通知页**：在 `maxbo iPhone` 上看过顶栏和首页一样高、第一条和首页对齐、顶部不淡；在 `maxbo test` 上临时把列表换成合成的行（不发请求、不看登录态）跑 UI 测试，点页签切换、左右滑动换页、慢慢拖不到一半留在原页、往下滚页签栏隐藏且原来页签栏那一截能拖、滚到顶栏下面有模糊、回到顶部模糊消失，都对。真实列表的滑动没看过（要登录）。
- **还没验证**：详情页和楼中楼真实页面上的底部工具栏随滚动收起和出现（要登录，只在关于页上模拟过）、要登录的列表页（首页、通知、热搜、用户主页、搜索结果）和网页里页签栏的隐藏和出现、换页签和返回时页签栏重新出现、真实列表上真的点页签时的再点一次和不在顶部时回到顶部（启动参数只模拟了 `Router.selection` 的设置；首页和通知页的合成列表上 UI 测试真的点过，见上）、从缩略图放大进入看图和下滑关闭（启动参数打开的看图没有缩略图）、写操作（点赞、评论、回复、删除、转发、发微博，按约定要用户同意并用指定的测试微博）、滚动翻页（要登录才有内容可滑，只看了代码路径）、实况照片（那一页时间线里没有）、视频地址过期后换新、真正的 `SUB` 自然过期（要用 `ALC` 换新的那条续期路径）、验证码、iPad 和横屏、字体大小调到最大时的排版。

## 6. 还没定的

- **分发**：PLAN §10 当初不做 iOS 的理由（App Store 基本上不了架，只能发无签名 IPA 自签，免费 Apple ID 每 7 天要重签）依然成立。要不要发、怎么发（无签名 IPA 进 Release、CI 构建），等用户决定。
- **CI**：`ci.yml` 还只跑 Android；iOS 的构建和测试要 macOS runner。
