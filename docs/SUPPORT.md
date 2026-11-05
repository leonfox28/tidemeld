# 叠澜 · Tidemeld 支持

叠澜（Tidemeld）是免费、开源、非官方的社交媒体聚合客户端，iOS 版使用 SwiftUI，界面为简体中文。项目与微博、X 及其运营方没有关联。

## 联系维护者

请在 [GitHub Issues](https://github.com/leonfox28/tidemeld/issues) 提交使用问题、功能建议或隐私问题。提交需要 GitHub 账号。

请提供应用版本、系统版本、设备型号、复现步骤和错误提示。截图请先遮挡个人信息。**不要提交密码、验证码、Cookie、完整网络抓包或私人微博内容。**

## 登录与使用

未登录时，“首页”直接以原生微博卡片显示游客可见的公开信息流，可以下拉刷新、查看图片和视频。微博目前只向游客提供首屏；查看更多、展开完整内容、查看用户资料及互动时会引导登录。也可打开“搜索”页看热搜，点热搜条目后浏览微博公开网页。登录后首页切换为关注动态，“搜索”顶栏右侧会显示搜索按钮，点击可输入关键词并查看原生搜索结果。

从首页左上角或“设置 → 账号管理”进入账号管理，添加时选择微博或 X，并在对应平台官方页面登录。同一平台可添加多个账号，也可同时登录不同平台。首页顶栏的下拉菜单选择“聚合 / 微博 / X”：聚合合并所有已登录账号，平台选项合并该平台的全部账号。

X 为接入原型，iOS 已实测单个真实账号的登录、原生读取和平台筛选；多账号真实合并、分页边界及 Android X 实机验证仍待完成。X 卡片的图片可原生查看，视频及互动打开对应账号的官方网页。遇到 X 拒绝访问或格式变化，先检查官方网页的账号状态，不反复自动重试。

验证码由你本人完成；叠澜不会自动处理验证码。出现频率限制时，请稍后再试。接口或登录流程可能随微博调整而变化。

图片占用较大时，可直接打开底部“设置”调整图片质量和缓存上限，或清除图片缓存。首页左上角现在进入账号管理。搜索、通知和发微博使用账号管理中选定的微博账号；信息流内微博互动使用该条目的来源账号。移除账号在账号管理中进行，其他账号不受影响。

## 内容与账号问题

微博内容由微博服务提供。遇到侵权、骚扰或其他不当内容，请使用微博官方的举报和黑名单功能；[微博社区管理中心](https://service.account.weibo.com/)提供相关规则和投诉信息。叠澜维护者不能替代微博删除服务器上的内容或恢复微博账号。

如果问题涉及 叠澜对内容的展示或应用自身行为，请通过上述 GitHub Issues 告知维护者。公开反馈时只提供必要的公开链接和问题描述，避免再次传播不当内容或私人信息。

## 隐私

详见 [叠澜隐私政策](PRIVACY.md)。维护者不运营接收用户微博数据的后端；应用使用微博服务时的数据处理与本地存储方式在政策中分别说明。

---

# Support in English

Tidemeld is a free, open-source, unofficial social media aggregator with Weibo support and an experimental X web integration. Its app interface is in Simplified Chinese. It is not affiliated with or endorsed by Weibo or X. Multiple accounts per platform are supported. The Home menu selects all accounts, Weibo, or X; each platform view combines all signed-in accounts on that platform. Single-account X authentication, native feed reading and platform filtering have been verified on iOS. Live multi-account merging, pagination boundaries and Android X access still need validation.

Without signing in, 首页 (Home) displays public posts using native cards, with pull-to-refresh and media viewing. Weibo currently limits guests to the first page; further reading, profiles and interactions prompt sign-in. 搜索 (Search) also offers trending topics that open public web results. After sign-in, Home switches to the following feed, and the button at the top right of Search opens a field for keyword searches with native results.

For support or privacy questions, [open a GitHub issue](https://github.com/leonfox28/tidemeld/issues). Include your app version, OS version, device model and steps to reproduce. GitHub issues are public and require a GitHub account. Never post passwords, verification codes, session cookies, private posts or unredacted screenshots.

Weibo handles account access and reports about content hosted on its service. Contact [Weibo's community support](https://service.account.weibo.com/) for those matters. Contact the Tidemeld maintainer for problems with the app itself. See the [privacy policy](PRIVACY.md) for how local storage and requests to Weibo work.
