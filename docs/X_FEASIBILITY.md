# X 接入可行性调研

调研日期：2026-11-05。依据 X / Apple 当前公开文档、开源项目的一手记录和本仓库代码。未使用真实 X 账号登录、未购买 API、未调用收费端点；下面的接口能力是文档结论，不是本项目实测结果。

## 结论

X 可以做有限接入，但目前没有同时满足“免费、纯客户端、完整原生体验、稳定公开分发”的已确认方案。应先做小范围验证，再决定原生聚合的投入。

| 路线 | 能提供的体验 | 主要限制 | 判断 |
|---|---|---|---|
| 官方 API + OAuth | 原生关注时间线、资料、帖子、部分互动 | 按内容量付费、功能差异、替代客户端条款 | 技术路线清晰；先解决用途许可和费用 |
| 官方网页 WebView / 系统浏览器 | 在同一应用内访问 X，由网页完成阅读和互动 | 无法直接合并成原生信息流；登录、媒体兼容需实测 | 适合作为接入验证及降级入口 |
| 用户网页登录态 + 非公开网页接口 | 理论上更接近官网，包括推荐流 | 接口变化、风控、条款与分发风险 | 有开源实现作为证据，不能视为稳定方案 |
| 第三方转售 API | 取决于供应商 | 用户凭据/内容离开设备，供应商依赖及授权不明 | 不符合当前项目纯客户端边界 |

若第一版必须提供微博与 X 混合的原生信息流，WebView 不能充当该功能已经完成的替代品。

## 官方 API

### 阅读和互动

- **关注时间线可读**：`GET /2/users/:id/timelines/reverse_chronological`，需用户授权，按时间倒序；文档范围为最近 3,200 条或 7 天。它明确不包含算法排序，不能承诺复现官网的 For You。用户发帖与提及也有专用端点。[时间线文档](https://docs.x.com/x-api/posts/timelines/introduction)
- **请求频率不是首要瓶颈**：上述首页端点当前列为每用户每 15 分钟 180 次，仍需按响应头退避，不能把该值当作固定承诺。[限流文档](https://docs.x.com/x-api/fundamentals/rate-limits)
- **原生手机端无需后端即可授权**：Native App 是 public client，支持 OAuth 2.0 Authorization Code + PKCE。最小阅读权限从 `tweet.read users.read offline.access` 开始，令牌本地加密保存；`offline.access` 提供刷新令牌。不能把 app-only Bearer Token 或 confidential-client secret 打包给所有用户。[授权文档](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code)
- **回复存在实质缺口**：2026-02-23 公告对自助接入的 `POST /2/tweets` 回复施加“原作者先提及该账号或引用其帖子”等条件，并对程序化提及、引用另设限制。不能因为用户手动点击就假设不受接口限制；Enterprise 不受该次调整影响。首版宜将不支持的互动引导到 X。[官方变更记录](https://docs.x.com/changelog#feb-23-2026)
- **通知与私信留到后续**：有提及、DM 和 Activity API，不等于完整复现官网通知中心。当前项目不设服务器、不后台轮询，应逐项核实端点、权限、前台使用方式，首版不承诺统一实时通知或私信。

### 费用

当前公开报价采用预充值按量计费；读取按返回资源数，不是每次请求。以下美元价格需在接入时再次核对控制台。[官方价格](https://docs.x.com/x-api/getting-started/pricing)

| 项目 | 当前公开单价 |
|---|---:|
| 读取帖子 | $0.005 / 条 |
| 读取用户资源 | $0.010 / 个 |
| 创建普通帖子 | $0.015 / 次 |
| 创建含 URL 帖子 | $0.200 / 次 |

**自行估算，仅算帖子读取**：单人每天读取 100 条当天尚未计费的帖子，30 天约 $15；1,000 人在内容不重叠的假设下约 $15,000 / 月。资料、回复等额外资源和写操作另计，不能将此当作总账单。

同一资源在 UTC 自然日内通常去重计费，但官方称其为软保证。跨用户重叠的具体计费归属及 expansions 的费用应以控制台实测核对。Owned Reads 的优惠要求授权用户同时拥有 developer app，且列出的适用端点不包括关注首页，不能给全部用户首页套用该折扣。应设置充值和支出上限。

让用户自带开发者应用/额度可以转移付费责任，但增加注册、支付、回调配置的门槛，也不能自动解决使用条款。免费开源本身不产生免费 API 资格。

### 用途与展示边界

2026-04-27 更新的开发者协议 III.A(c) 仍限制用授权材料创建 X 应用的替代或类似服务。**跨平台聚合是否获得允许，不能仅由“有 API”“付了钱”“非商业”推断。** 面向公众推出原生阅读/互动客户端前，应把实际使用场景交由 X 确认；本次没有取得该确认。[开发者协议](https://docs.x.com/developer-terms/agreement)

展示帖子需保留来源、作者、时间与原帖链接；X 卡片上的跨平台操作按钮也受限制。混合信息流需清楚标识平台，不能将 X 帖子伪装成微博卡片或附加“微博点赞”等按钮。缓存还需处理编辑、删除及内容不可用状态。[展示要求](https://docs.x.com/developer-terms/display-requirements)、[开发者政策](https://docs.x.com/developer-terms/policy)

## 能否复用微博的 Cookie 路线

公开项目 [Twikit](https://github.com/d60/twikit) 确有调用 X 内部接口的实现，说明该路线有技术先例。它记录了 `HomeTimeline` / `HomeLatestTimeline` 等操作，但并非 X 授权的稳定接口。[项目端点记录](https://github.com/d60/twikit/blob/main/ratelimits.md)

工程成本不只在读取 Cookie：还涉及网页操作标识、features、复杂时间线条目、翻页游标、请求校验和会话变化。项目维护记录已有搜索请求方式、transaction 逻辑、响应解析变化的修复；这些只能证明维护负担，不能保证今天的所有账号都可用。[维护记录](https://github.com/d60/twikit/pull/412)

X 当前服务条款明确限制未经书面许可的抓取和绕过技术限制。网页登录成功、请求量小或仅在本机操作，都不能自动消除该限制。项目既定的“不绕过验证码、不伪造风控、不伪装官方 App”边界继续适用；出现必须绕过限制才能运行的情况，应停止该路线。[X 服务条款](https://x.com/en/tos)

第三方库的开源许可也不等于获得 X 平台使用许可。结合下面 Flare 的实际实现，网页会话路线值得优先做原生读取验证；它仍未在本项目实测，不应把参考项目的实现直接等同于稳定性或分发保证。

### Flare 源码核查（2026-11-05 补充）

核查的是 [DimensionDev/Flare](https://github.com/DimensionDev/Flare)，固定版本为 `9cba58812449463bfa83e48f094bc5cdf854e399`。这次只阅读源码，没有运行 Flare、登录 X 或复制其实现。

**Flare 确实采用与本项目微博相近的“网页登录 + Cookie + 网页内部接口 + 原生展示”方案。** 它不是只包一个 X 网页，也不是通过购买官方开发者 API 额度实现时间线。前文官方 API 的价格、推荐流缺口及回复限制，不能直接套用到这条网页接口路线。

1. 登录提供器只声明 `WebCookie`，打开 `https://x.com/i/flow/login`。拿到 Cookie 后检查 `auth_token` 和 `ct0`，再请求 `/home` 获取用户 ID、读取用户资料并建立本地账号，避免仅凭 Cookie 存在就判定登录成功。[登录提供器](https://github.com/DimensionDev/Flare/blob/9cba58812449463bfa83e48f094bc5cdf854e399/social/xqt/src/commonMain/kotlin/dev/dimension/flare/ui/presenter/login/XQTLoginProvider.kt)
2. Android 通过 `CookieManager`、iOS 通过 WebKit 的 `httpCookieStore` 读取网页登录态。这与我们的现有技术栈兼容；Flare 的 Kotlin Multiplatform 不是实现该方案的必要条件。[Android 登录页](https://github.com/DimensionDev/Flare/blob/9cba58812449463bfa83e48f094bc5cdf854e399/app/src/main/java/dev/dimension/flare/ui/screen/serviceselect/WebCookieLoginScreen.kt)、[iOS 登录页](https://github.com/DimensionDev/Flare/blob/9cba58812449463bfa83e48f094bc5cdf854e399/appleApp/ios/UI/Screen/WebLoginScreen.swift)
3. 网络层携带 Cookie，将 `ct0` 用于 CSRF 请求头，使用网页客户端 Bearer 与浏览器请求头，调用 X 的内部 GraphQL 等接口。主时间线来自 JSON 响应，而非从页面 DOM 提取每条帖子；这里的 Bearer 不是用户申请的开发者 API 凭据。[XQTService](https://github.com/DimensionDev/Flare/blob/9cba58812449463bfa83e48f094bc5cdf854e399/social/xqt/src/commonMain/kotlin/dev/dimension/flare/data/network/xqt/XQTService.kt)
4. `HomeLatestTimeline` 与 `HomeTimeline` 分别有读取实现，解析帖子与 cursor，再映射为共同的 `UiTimelineV2` 展示模型。按时间的关注流允许加入混合流，排序流则不直接加入，值得参考其分页与排序边界。[时间线加载器](https://github.com/DimensionDev/Flare/blob/9cba58812449463bfa83e48f094bc5cdf854e399/social/xqt/src/commonMain/kotlin/dev/dimension/flare/data/datasource/xqt/HomeTimelineRemoteMediator.kt)
5. 额外复杂度包括 GraphQL query ID、features、嵌套响应以及 `x-client-transaction-id`。该版本尝试从另一 GitHub 项目读取公开参数并在本地生成该请求头；生成失败时会省略此头继续发请求。这既说明存在额外网络依赖，也意味着仅阅读代码无法断言哪些请求今天必须带它。应在真实会话验证中区分必要的协议参数与绕过限制的行为，不能直接照搬整个模块。[请求参数实现](https://github.com/DimensionDev/Flare/blob/9cba58812449463bfa83e48f094bc5cdf854e399/social/xqt/src/commonMain/kotlin/dev/dimension/flare/data/network/xqt/elonmusk114514/ElonMusk1145141919810.kt)

**对本项目的建议调整**：优先验证 `XWebProvider`，范围仅为用户手动网页登录、身份校验、关注流首屏及下一页、图片/视频、重启恢复、过期/限流提示。先隔离微博与 X 的 Cookie、账号和游标，验证通过后再接统一原生信息流；推荐流和写操作另做验证。这条路线无需购买官方 API 读取额度，也无需自建聚合服务器，但需要承担网页接口适配工作。Flare 使用 AGPL-3.0；当前项目使用 GPL-3.0，借鉴设计不等于已决定直接移植其代码。

## 对当前代码的影响

Android 与 iOS 都是微博专用的单会话结构：`AppGraph` 直接持有 `WeiboApi` / `WeiboAPI`、微博时间线和互动控制器。现有分页、媒体查看器、主题和部分布局可复用，接口与会话不能简单换域名。

需要的最小结构调整：

1. 平台与账号联合键：`Platform + accountId`；帖子键同样带平台，避免不同平台 ID 撞车。第一阶段每个平台一个账号即可。
2. `WeiboProvider` / `XProvider` 分离，声明各自支持的能力；按能力显示阅读、回复、引用等操作。网络头、凭据和限流按平台隔离。
3. 保留独立的源数据模型，将通用作者、正文片段、媒体、引用和原帖 URL 映射到展示模型；微博 HTML 与 X entities 不共用同一个正文解析器。
4. 若做混合流，每个平台分别持有 cursor、缓冲区、结束与错误状态；只合并已经加载的可排序内容，不能拿一个全局 `maxId` 给两边翻页。某个平台失败不阻塞另一边。
5. **必须修复退出登录的隔离**：Android `WebViewCookies.clearAll()` 调用 `removeAllCookies`；iOS `WebKitCookies.clearAll()` 删除默认存储全部 Cookie。直接加入 X 会导致退出微博可能同时清除 X 网页登录态。应按域名或独立存储管理。
6. 草稿、点赞覆盖、缓存权限、路由和退出后的清理按平台/账号归属，旧微博会话迁移需明确处理。

## 建议的验证顺序

1. 先定义平台入口与会话隔离，保留微博现有体验；结合 Flare 源码核查，优先做上述网页会话的原生读取验证。官方网页作为登录、验证和失败回退入口；网页能打开与原生流能读取分别验收。
2. 若选择官方 API 路线，则先确认官方用途许可与预算，再用有限额度验证 PKCE、首页首屏/下一页、资料/媒体、令牌刷新、撤销授权、429、余额耗尽及删除帖。记录实际账单，不用推算代替实测。这是另一条数据源路线，不是网页会话方案的前置条件。
3. 最小原生范围是关注时间线、资料、帖子详情、媒体和原帖跳转。推荐流、完整通知、私信、任意回复不列入首版保证。
4. 验证通过后再接入共同展示模型和本地合并，避免先大改 UI 再发现数据源不可用。

纯客户端还要求设备本身能访问 X；本次没有测试用户设备的网络可达性。iOS 分发需单独评估：Apple 5.2.2 要求第三方服务使用获得许可，4.2 / 4.2.2 对简单网页包装或内容/链接集合有限制。WebView 可作局部功能，但不能据此保证整个应用能上架。[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## 实现进展（2026-11-05，v0.14.0 开发版）

用户确认采用网页登录路线，且同一平台支持多个账号、首页合并全部已登录账号。两端已独立实现账号存储、原生聚合信息流、平台筛选、X 登录校验和关注流读取；未复制 Flare 代码。网页请求只允许 X 自身主机，关闭携带凭据的自动重定向，401 标记过期、429 退避，403 显式提示检查登录/安全验证。协议标识与 features 存在共享 `protocol/x-web.json`。

当前实现不依赖 Flare 的第三方 transaction-id 配对数据，也未实现 transaction-id 生成。若 X 当前要求该请求头或调整查询标识，读取可能被拒绝。真实账号的登录、首页数据和分页仍需实测；合成测试覆盖账号隔离、独立游标、去重、失败恢复、媒体/引用解析和请求限制，不证明真实服务已可用。视频和写操作暂交给对应账号的官方网页，不声称与微博原生功能对等。
