# 验证记录

日期：2026-10-13（Asia/Shanghai）。

后端协议基线：

```text
Repository: http://10.10.10.10:33000/sean/JavStrm
Branch: main
Commit: 00c574eedc7613150a98d3e93fafe61a28ade34a
```

## 已通过

- Swift 6.3.1 在本机 macOS 上编译 `JavStrmCore` 和验证程序。
- 地址验证：HTTP / HTTPS、缺省 scheme、子路径、查询参数编码、路径段编码、非法 URL、路径越界拒绝。
- 解析后端仓库提供的 7 份固定 JSON：媒体库、作品详情、工作流、订阅、115 账户、磁力、离线任务。
- 模拟网络：登录 JSON、接收 Cookie、后续 Cookie 请求、App 会话过期清理、115 业务 401 保留 App 登录、浏览器会话同步、错误服务检测、null 列表、图片代理 URL。
- SSE：注释、事件类型、多行数据、空行边界、数据限制、URLSession 字节流接收。解析采用字节分隔，避免本机 AsyncLineSequence 丢弃空行而不发出事件的问题。
- `AppSession.swift` 与 `CredentialStore.swift` 使用真实 Foundation、Observation 和 Security 框架完成 Swift 6 严格类型检查。
- App 全部 Swift 文件完成语法解析。
- 使用 macOS SDK 对临时转换的平台对应 SwiftUI / WebKit 代码进行辅助类型检查。只替换 iOS 专用修饰符、图片 / 视图类型以及 UIKit 桥接；真实工程文件不作这些替换。该检查不能代替 iOS SDK 编译。
- Info.plist、PrivacyInfo.xcprivacy、project.pbxproj 通过 `plutil` 检查。
- Scheme / workspace XML、资源 JSON、工程 Swift 源文件引用完整性检查。
- 1024 × 1024 应用图标已生成并进行可视检查。
- 对提供的 Gitea 地址执行只读服务探测，正确报告该地址不是 JavStrm API。
- 用户补充实际服务地址 `http://10.10.10.10:10380`；公开健康接口返回 `status=ok`，原生 APIClient 探测返回 `enabled=true, authenticated=false`。
- 按用户最新要求取消默认服务地址，首次启动输入框为空，只记住用户自行填写的地址。
- IPA 构建和容器检查脚本已添加。实际设备构建及安装状态另行记录，脚本存在不代表已经生成 IPA。

可重复执行的主要检查入口：

```bash
bash scripts/verify.sh
```

## 尚未验证

- iOS SDK 下完整构建、模拟器运行和真机安装。
- 真实部署服务的登录、115 账户状态、网络权限提示、业务写操作和 Web 管理交互。
- iPhone / iPad 各尺寸布局、大字号、横屏、后台快照和模态页面遮罩。
- HTTPS 反向代理和真实 SSE 长连接的网络中断及恢复。

初次验证时本机只有 Command Line Tools；用户随后授权下载 Xcode 并生成未签名 IPA。已从官方 App Store 下载 Xcode 27.0（27A266a），安装包通过 Apple 签名检查，并成功安装至 `/Applications/Xcode.app`。App Store 的旧安装服务连接报错后，使用保留的官方安装包完成安装。

当前设备构建等待 Xcode 首次初始化的系统管理员确认（`xcodebuild -license accept` 和 `xcodebuild -runFirstLaunch`）。已启动构建等待进程，初始化完成后自动执行 `bash scripts/build_ipa.sh unsigned`，日志写入 `build/unsigned-build.log`。尚未生成 IPA，不能将安装成功等同于 iOS 编译成功。

真实服务地址已确认，但没有提供服务端登录凭据。本机初始检查没有有效代码签名身份或现有设备描述文件。下载日志位置为 `/Users/sean/Downloads/javstrm-xcode-install.log`，此文件不包含 Apple 账户或管理员密码。

## 接口对应

| 客户端模块 | 服务端接口 |
| --- | --- |
| 登录 | `GET /api/auth/config`、`POST /api/auth/login`、`POST /api/auth/logout` |
| 媒体库 | `GET /api/library/tabs`、`GET /api/library/movies`、`POST /api/library/scan`、`POST /api/library/movies/:id/crop-poster` |
| 发现与详情 | `GET /api/discover/movies`、`GET /api/discover/search`、`GET /api/discover/movies/:id` |
| 磁力与离线 | `GET /api/discover/movies/:id/magnets`、`POST /api/discover/movies/:id/offline`、`GET /api/offline/tasks`、`POST /api/offline/tasks/:id/terminate` |
| 订阅 | `GET /api/subscriptions`、`POST /api/subscriptions`、`PATCH /api/subscriptions/:id`、`DELETE /api/subscriptions/:id`、`POST /api/subscriptions/:id/enqueue`、`GET /api/subscriptions/actors/:id/feed` |
| 工作流 | `GET /api/tasks`、`GET /api/tasks/events`、`POST /api/tasks/:id/pause`、`POST /api/tasks/:id/resume`、`POST /api/tasks/:id/terminate` |
| 工具 | `POST /api/organize`、`POST /api/local/organize`、`POST /api/strm-scrape`、`POST /api/quick-strm/generate` |
| 快速 STRM 任务 | `GET /api/quick-strm/jobs`、`POST /api/quick-strm/jobs/:id/cancel` |
| 账号与文件 | `GET /api/pan/account`、`GET /api/pan/files`、`GET /api/files/local` |
| 日志与图片 | `GET /api/logs`、`GET /api/image`、`GET /api/library/artwork/:key` |
| 高级管理页面 | `/settings`、`/tools`、`/files`、`/tasks` |

## 媒体库横向图与封面裁切变更验证

日期：2026-10-13（Asia/Shanghai）。

- 已核对本地后端 `web/src/features/library/poster-crop-dialog.tsx`、`web/src/api/library.ts` 和 `internal/library/library.go`：裁切源优先使用 fanart，回退 cover；默认右侧 2:3 选框；保存提交原图像素坐标到 `POST /api/library/movies/:id/crop-poster`。
- 客户端详情改为 3:2 横向图容器，完整显示 fanart / cover；卡片继续优先展示 poster。裁切选框使用原图像素保存状态，界面尺寸改变时保持所选区域。
- 已添加回归用例：横向图及海报选源、空 URL 回退、仅有 poster 时禁止裁切、默认选区、移动和缩放边界、小图与竖图、取整后的像素边界、带会话的裁切请求、空成功响应及服务端错误。
- 本次通过 Tree-sitter 对 22 个 Swift 文件进行语法检查；Xcode 工程源文件引用、Scheme / workspace XML、资源 JSON 与 property list 检查通过。语法检查不等于 Swift 编译器类型检查。
- 本次环境未找到 Xcode / Command Line Tools，`bash scripts/verify.sh` 在启动 Swift 时失败。新增 Swift 回归用例尚未执行，iOS 编译、拖动交互和真实服务保存仍需在具备 Xcode 的环境验证；此前的构建记录不代表本次变更已完成编译。

## 页面精简与任务处理详情变更验证

日期：2026-10-13（Asia/Shanghai）。

- 已移除媒体库、发现、订阅、任务和设置页的介绍区，移除媒体库作品及处理数量统计，将媒体库置顶导航标题改为“媒体库”。
- 已核对本地后端 `internal/tasks/workflow.go`：所有工作流响应都会附带 `scan`，包括其他类型任务。客户端现在按 `type` 选择进度字段，避免空扫描数据覆盖整理、刮削等任务的真实进度。
- 已参照后台 `web/src/api/task-history.ts`、`web/src/features/task-history/page.tsx` 和 `internal/tasks/history.go`，接入逐项结果接口，显示源文件、目标文件、STRM / 元数据路径、演员、目录、媒体项标识及完整错误信息。详情支持分页、下拉刷新和运行期间每 5 秒刷新已加载页；订阅批量任务显示响应内的失败条目。
- 新增回归用例覆盖 10 类任务的进度选择（包括非扫描任务携带空 `scan`）、中文标签、路径数组、内嵌失败结果、逐项结果解码、8 类结果接口路由、分页参数、会话 Cookie、空结果和服务端错误。
- Tree-sitter 对 23 个 Swift 文件完成辅助语法检查。测试文件中的原始字符串及 `nonisolated(unsafe)` 在内存中做等价语法适配以兼容旧版语法规则，仓库源文件没有为此改写。此检查不能替代 Swift 编译器类型检查。
- 页面移除项、JSON fixtures、资源 JSON、property list、Scheme / workspace XML、Xcode 工程源文件引用及 `git diff --check` 检查通过。
- `bash scripts/verify.sh` 因本机缺少 Xcode / Command Line Tools 而无法启动 Swift。新增 Swift 回归用例尚未执行；本次没有生成 IPA，也没有进行 iOS 编译或真实服务登录后的界面验证。

## 发现页卡片状态与默认自动下载变更验证

日期：2026-10-13（Asia/Shanghai）。

- 已参照后台 `web/src/components/movie/movie-card.tsx`、`movie-subscribe-button.tsx` 和 `internal/api/discover.go`：发现页卡片右上角显示订阅、已订阅、已加入离线或已入库；已入库优先。可订阅入口按有磁力资源或未发售作品判断，已有订阅及下载状态继续显示。
- 卡片订阅按钮与详情导航为独立控件，提交期间禁止重复点击。统一从订阅分页接口读取状态，并通过 `POST /api/discover/movie-states` 每批最多 100 部作品查询当前入库及处理状态；返回详情页、下拉刷新和任务版本变化时刷新，过期请求不会覆盖新状态。
- 卡片新建作品订阅明确提交 `auto_download=true`，作品详情的自动下载开关默认开启，用户仍可关闭开关再订阅。
- 新增 Swift 回归用例覆盖状态优先级、未发售作品和无资源作品、当前状态覆盖旧列表状态、超过 100 条订阅的分页、自动下载默认开启及显式关闭、状态请求分批、会话 Cookie、空列表和服务端错误。
- Tree-sitter 对 23 个 Swift 文件完成辅助语法检查；测试原始 JSON 字符串及 `nonisolated(unsafe)` 在内存中适配旧语法规则，仓库文件未作这些替换。JSON fixtures、资源 JSON、property list、Scheme / workspace XML、Xcode 源文件引用和 `git diff --check` 检查通过。
- `bash scripts/verify.sh` 因本机缺少 Xcode / Command Line Tools 而无法启动 Swift。新增回归用例尚未执行，本次未进行 iOS 编译、真实界面交互验证或 IPA 构建。

## 媒体库卡片点击区域与无磁力订阅入口修复

日期：2026-10-13（Asia/Shanghai）。

- 媒体库卡片封面独立打开裁切窗口，番号及标题区域独立进入详情页；已移除卡片和详情工具栏的裁切按钮。封面隐藏或没有可裁切图片时保留禁止裁切的行为，卡片不显示评分。
- 抽取共享的番号及标题视图，媒体库与发现页保持相同文字样式；文字点击区域覆盖整个文字块。
- 发现页订阅入口不再依赖磁力数量或发行状态。磁力数量为 0、null 或缺失时均显示订阅按钮，并继续优先显示已入库、已加入离线及已订阅状态。
- 更新回归用例覆盖无磁力资源的已发售、未发售、未知发行状态、异常订阅及磁力字段为 null 或缺失。
- 使用现有 Tree-sitter 对 23 个 Swift 文件完成辅助语法检查，测试原始 JSON 字符串及 `nonisolated(unsafe)` 仅在内存中适配语法规则。JSON fixtures、资源 JSON、property list、Scheme / workspace XML、Xcode 源文件引用及 `git diff --check` 检查通过。
- 本机仍缺少 Xcode / Command Line Tools，Swift 回归用例及 iOS 编译未执行；未安装依赖、运行浏览器测试或构建 IPA。
