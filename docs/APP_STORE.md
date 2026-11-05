# App Store 首发准备

更新：2026-11-05。本文是发布工作记录，不是已经符合所有要求、已经提审或已经获批的声明。

## 已确认的方案

| 项目 | 方案 |
|---|---|
| 产品 | maxbo，非官方微博客户端 |
| 首发地区 | 仅美国，其他地区不自动勾选 |
| 价格 | 免费，无内购、订阅或捐赠入口 |
| 平台 | iPhone、iPad，iOS / iPadOS 26+ |
| 界面 / 商店主语言 | 简体中文；另备英文商店文案 |
| Bundle ID | `io.github.leonfox28.maxbo`（已注册） |
| SKU | `maxbo-ios` |
| App Store Connect | [maxbo · 6830942092](https://appstoreconnect.apple.com/apps/6830942092/distribution)，已创建，准备提交 |
| 开发者团队 | 当前 Mac 账号，`AVHU3J463N`；不是开发证书姓名后的个人标识 |
| 版本 / 构建 | `0.13.1` / `1`，上传后若重新构建，递增构建号 |
| 类别 | 社交 |
| 发布方式 | 手动发布，审核通过后再确定公开日期 |
| 支持入口 | [GitHub Issues](https://github.com/leonfox28/maxbo/issues)，无需公开个人邮箱 |

GitHub 的 `noreply` 地址用于提交身份，不是接收支持请求的邮箱。App Review 联系人需要真实、可接收的邮箱及联系电话，填写在 App Store Connect 的审核联系字段中，不写进仓库。

## 已准备的文件

- [完整隐私政策](PRIVACY.md)：应用中随包提供离线版本；“关于”和登录页可进入。
- [支持页面](SUPPORT.md)：中文与英文说明、反馈入口及账号问题指引。
- [中文商店文案](app-store/zh-Hans.md)、[英文商店文案](app-store/en-US.md)、[英文审核备注草稿](app-store/review-notes.md)。
- `ios/Maxbo/PrivacyInfo.xcprivacy`：应用自身 UserDefaults 使用理由 `CA92.1`；不代替 App Store 隐私标签。
- `ios/ExportOptions-AppStore.plist`：导出到本机，不自动上传，不自动改变构建号。

隐私和支持 URL 已发布到公开仓库的 `main/docs/PRIVACY.md`、`main/docs/SUPPORT.md`。2026-11-05 使用不带登录凭据的 HTTP 请求验证，两页均返回 200；隐私链接已保存到 App Store Connect。之后修改 URL 时仍需重新验证公开访问。

## 提审前必须完成

### 内容举报与屏蔽

目前代码没有完整的举报、不当内容过滤和屏蔽用户功能；支持页链接到微博社区管理中心不能替代这些功能。按 [审核指南 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content) 补齐后再提交。

实施顺序：

1. 从当前微博官方页面核实举报和黑名单流程。微博、评论、用户主页都应提供可发现的入口；打开与当前对象对应的官方举报页，不能只跳到帮助首页。旧版 URL 尚未验证，不能凭猜测新增写接口。
2. 实现按账号持久化的本地屏蔽及管理列表；同时核实官方黑名单操作，准确说明本地隐藏与服务端屏蔽的区别。所有列表、转发嵌套和评论回复都需处理；账号切换隔离。不要将本地隐藏宣传为阻止服务端骚扰。
3. 提供适合产品的内容过滤机制，验证服务端过滤和客户端措施的覆盖范围；不能仅用几个关键词宣称已具备完整审核能力。
4. 维护者确立内容安全反馈的处理流程，实际监测支持入口并及时响应。公开 Issue 不适合接收敏感证据，需要时提供私密接收途径。
5. Android 与 iOS 行为同步，以合成数据测试，真实举报或拉黑前另按项目约定取得用户授权，避免误举报他人。

### 审核登录和第三方服务

- 2026-11-05：首页追加原生游客信息流。通过微博正常游客流程建立会话并确认 `login:false`，从移动端公开接口读取首屏，复用原生微博卡片和媒体查看；用户不需要先手动打开网页。第二页实测要求登录，因此底部明确提示；关注时间线、通知和写操作仍需解决审核访问。实现及实测见 [PLAN §8](PLAN.md#8-待验证项m1-实测结果2026-10-13)。
- 2026-11-05 增加有限游客浏览：未登录可打开“搜索”看原生热搜榜，点热搜进入 `m.weibo.cn` 官方网页；关键词输入入口仅在登录后显示。实测无 Cookie 热搜返回 `ok:1`，原生搜索返回 `ok:-100`；无真实账号的测试模拟器能查看网页首批结果，继续翻页会转到登录页。没有绕过游客限制，也未将网页游客 Cookie 当作账号登录态。此路径不能代替关注时间线、通知和写操作的审核访问。
- 2026-11-05 用户说明：专门小号仍需要手机验证码，询问能否免登录。审核访问方案尚未确定，不能仅凭提供账号密码就标记完成。
- 方案 A：如果能提供可独立登录的微博审核账号，通过 App Store Connect 填凭据，并用新会话验证。需要维护者临时扫码或收短信的流程无法保证审核员独立访问。
- 方案 B：事先向 Apple 说明第三方短信验证限制，申请用完整内置演示模式代替账号。[2.1(a)](https://developer.apple.com/app-store/review/guidelines/#app-completeness) 对因法律或安全义务无法提供账号的情况要求事先取得 Apple 同意；短信验证是否被认可尚未确认。[英文请求草稿](app-store/reviewer-access-request.md) 已准备，尚未发送。
- 如果采用演示模式，应公开提供、明确标注示例数据，覆盖时间线、详情、搜索、媒体与互动流程；所有模拟写入只影响本地演示数据，真实登录功能保留。当前代码尚未实现，不可在审核备注里声称已有。仅几张静态截图或只开放设置页不能替代完整访问。
- 不共享开发者主账号、现有设备 Cookie，不做验证码绕过或仅对审核员隐藏功能的路径。
- 记录微博当前服务条款允许使用的依据；若 Apple 要求许可材料，需要提供真实材料。[5.2.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property) 仍适用，其他客户端已上架不能作为 maxbo 已获得许可的证明。
- 明确注册/注销责任：maxbo 不创建自己的账号；核对官方网页登录页面是否暴露账号创建流程，并按最终流程核实账号删除要求。

### 隐私标签与年龄分级

不能因维护者无后端而直接勾选“不收集数据”。Apple 要求考虑应用及第三方的数据实践，包括特定服务的嵌入网页。[官方说明](https://developer.apple.com/app-store/app-privacy-details/)

| 路径 | 已知数据 | 需要核实的披露 |
|---|---|---|
| 官方登录网页 | 用户输入的登录信息、Cookie、网络信息直接交给微博 | 联系信息、标识符及网页实际收集；用途和保留方式 |
| 账号与写操作 | 用户 ID、文字、评论、选中的照片 | 标识符、用户内容；功能用途及与账号关联 |
| 搜索与浏览 | 搜索词、请求路径、账号 Cookie、IP / 请求头 | 搜索历史、使用数据及服务端保存情况；不能凭请求存在推断所有保留用途 |
| 本地设置、缓存、草稿 | 保存在设备 | 仅本地保存不等于向维护者收集 |
| 分析与广告 | 原生端无统计、广告 SDK；微博网页可能另有处理 | 不能将原生端无 SDK 推断成网页也不跟踪；需核实后填跟踪声明 |

年龄分级按 [当前问卷](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/) 如实回答 UGC、网页访问、互动和可能出现的内容；没有年龄验证或家长控制就不能声称有。不要为了分级较低而关闭问卷项目。最后由问卷计算，必要时提高最低年龄。

### 截图、发布前验收

- 准备 iPhone 和 iPad 的真实应用截图，覆盖时间线、详情与媒体、搜索、设置；界面与实际版本一致。
- 只用有权展示的内容；合成演示数据应标明示例，不截取当前账号的私人内容或他人头像用于营销。
- 按 App Store Connect 当前要求提供机型尺寸；验证应用图标无 alpha、元数据语言与版本正确。
- 用 Release 版验证登录、浏览、选图及写操作、注销本地会话、内容安全入口、离线隐私页、iPad/横屏、最大字号、视频与画中画。写操作遵守 CLAUDE.md 的测试目标及授权约定。
- 确认公开支持/隐私链接已上线，完成隐私标签、年龄问卷、内容权利、出口合规及审核联系方式，再上传最终构建和提审。

## 构建与导出

在 `ios/` 执行。团队 ID 通过命令传入，工程不绑定维护者账号。自动签名使用 Xcode 已登录的开发者账号，证书和密钥不进入仓库。

```sh
xcodegen generate
xcodebuild test -project Maxbo.xcodeproj -scheme Maxbo \
  -destination 'platform=iOS Simulator,id=7D96F02A-891D-4A38-B4E5-850A081A04B8' \
  -derivedDataPath build/store-prep -collect-test-diagnostics never
xcodebuild archive -project Maxbo.xcodeproj -scheme Maxbo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/app-store/Maxbo.xcarchive \
  -derivedDataPath build/store-release DEVELOPMENT_TEAM=AVHU3J463N -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/app-store/Maxbo.xcarchive \
  -exportPath build/app-store/export -exportOptionsPlist ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

归档、导出成功不等于 App Store 上传校验或内容审核成功。使用 Organizer / Transporter 上传前，核对版本、构建号和上述清单；上传与“添加以供审核”是独立步骤。

## 验证记录

- 2026-11-05：iOS 73 项单元测试通过；Release 真机目标归档成功。
- 2026-11-05：Android `spotlessCheck lint testDebugUnitTest assembleDebug` 全部通过，377 项测试无失败；构建后已停止 Gradle daemon。
- 2026-11-05：正式 Bundle ID 与 App Store Connect 应用记录已创建；中文描述、关键词、支持链接、版本 0.13.1、社交类别、副标题及手动发布方式已保存。
- 2026-11-05：价格已设为 USD 0.00；供应范围仅美国，后台显示“供应情况（1 个国家或地区）”，美国状态为“App 发布时供应”。Mac 和 Apple Vision Pro 分发未开启，首发先覆盖已确定的 iPhone / iPad。
- 2026-11-05：App Store 分发 IPA 导出成功，位于 `ios/build/app-store/export/Maxbo.ipa`。核对 Bundle ID、0.13.1 (1)、iPhone/iPad、随包隐私政策和隐私清单；图标无 alpha，归档签名校验通过。修复 XcodeGen 默认英文，安装包开发语言已确认为 `zh-Hans`。
- 2026-11-05：在无真实账号的 `maxbo test` 模拟器检查了离线隐私页，正文、滚动和末尾支持入口正常。尚未上传二进制或提交审核，真实账号及内容安全验收待完成。
- 2026-11-05：增加游客热搜及公开网页浏览后，iOS 76 项测试通过，Android 全量格式、lint、380 项单元测试与 Debug 构建通过。在无真实账号的 `maxbo test` 模拟器确认热搜及点击后的公开网页能加载；Release 重新归档、导出和签名校验通过。游客网页继续翻页会要求登录，审核访问问题仍需解决。
