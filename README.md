# JavStrm for iOS

JavStrm 的 SwiftUI 原生 iOS 客户端。App、工程、Scheme 与桌面显示名称均为 **JavStrm**。

支持 iOS 17 及以上的 iPhone 和 iPad，采用 Swift 6、Observation、URLSession 和系统 Keychain，不依赖第三方库。

## 已实现

| 功能 | 实现 |
| --- | --- |
| 连接与登录 | 自定义 HTTP / HTTPS 服务地址、反向代理子路径、服务类型检查、用户名密码登录、自动恢复会话 |
| 媒体库 | 海报网格、横向图详情、2:3 封面裁切与服务端保存、目录筛选、新入库筛选、分页加载、已加载内容搜索、扫描任务 |
| 发现 | 分类浏览、热门 / 最新 / 评分排序、服务端搜索、分页加载、作品详情、卡片订阅与入库 / 离线状态 |
| 订阅 | 作品和演员订阅、分页列表、自动下载开关、暂停演员追踪、演员更新列表、单项检查并入库 |
| 115 离线下载 | 查看磁力资源、分享磁力、确认提交、下载进度、终止任务 |
| 任务 | SSE 实时快照、断线重连、轮询补偿、工作流进度、支持类型的暂停 / 恢复 / 终止 |
| 整理工具 | 原生配置与启动 115 / CloudDrive2 整理、本地整理、STRM 刮削、按组快速生成、空目录清理、Emby 演员补全 |
| 系统管理 | 原生 115 扫码登录、账号与容量、下载 / 整理目录选择及清除、退出网盘登录、网盘和本地文件浏览、日志查看 |
| 服务端设置 | 原生代理测试、刮削源、订阅偏好、整理及定时规则、Emby 集成和封面、配置导入导出、缓存清理 |
| 文件管理 | 原生本地 / 115 目录浏览、选择目标、批量复制 / 移动 / 删除、单项重命名、逐项失败结果 |
| 任务历史 | 原生工作流历史搜索与分页、逐项处理结果、快速 STRM 历史及结果分页 |
| 隐私 | 默认隐藏封面且不请求图片；后台独立遮罩覆盖主界面和弹窗；密码不保存；Cookie 保存于本机 Keychain |

设置中的「登录网盘与配置目录」进入原生页面，可选择扫码方式、查看登录二维码，并在网盘目录中逐层浏览、分页及保存下载 / 整理目录。登录轮询在离开页面或进入后台时停止，返回前台继续查询；二维码过期或取消后可重新获取。退出 115 账号不会退出 App 的服务器登录。

「STRM 与 Emby 工具」「服务端完整设置」「文件复制、移动与管理」均进入 App 原生页面。配置编辑保留未修改字段，支持 STRM 生成组、定时计划、Emby 路径映射和收藏转移组；工具页保存配置后启动服务端任务。Emby 封面在 App 内生成预览并上传，隐藏封面时不能生成或查看预览。任务历史支持浏览和处理结果查看，暂未提供历史删除或整理结果纠错操作。

发现卡片不论是否已有磁力资源都可订阅，默认开启自动下载。创建订阅成功后立即显示「已订阅」并检查资源；暂时没有匹配资源时保留订阅，由服务端继续定时检查，已有下载或入库时更新对应状态。媒体库卡片点击封面进入裁切，点击番号或标题进入详情；详情页保留裁切按钮。

此版本没有集成视频播放器。媒体播放继续使用已配置的 Emby、Infuse 等播放客户端。

## 打开与运行

1. 在安装完整 Xcode 的 Mac 上打开仓库根目录的 `JavStrm.xcodeproj`，选择 **JavStrm** Scheme。
2. 在 **Signing & Capabilities** 中选择自己的 Team。默认 Bundle ID 是 `com.sean.javstrm`，需要时可修改为自己账号可用的标识。
3. 选择 iPhone / iPad 模拟器，或已开启开发者模式的真机，运行项目。
4. 首次启动时填写自己部署的 JavStrm Web 服务地址；App 不预设服务器。若服务启用登录，再输入服务端用户名和密码。后续启动会记住已填写的地址。
5. 连接局域网服务时允许本地网络权限。真机需能够通过当前 Wi-Fi / VPN 访问服务器。

**`http://10.10.10.10:33000/sean/JavStrm` 是 Gitea 源码仓库地址，并不是业务 API 地址。**

用户已确认实际部署地址是 `http://10.10.10.10:10380`。只读检查中 `/api/health` 返回 `{"status":"ok"}`，`/api/auth/config` 返回 `{"authenticated":false,"enabled":true}`。此地址仅用于部署验证记录，客户端不预设该地址。

正确部署的服务应在 `<服务地址>/api/auth/config` 返回如下 JSON，而不是 HTML：

```json
{"enabled":true,"authenticated":false}
```

若服务关闭了登录门禁，`enabled` 为 `false`，客户端直接进入主界面。支持 `https://example.com/javstrm` 等代理子路径，前提是反向代理和服务端 Web 页面已按该路径配置。

## 目录

```text
JavStrm.xcodeproj/            已生成的 Xcode 工程与共享 Scheme
JavStrm/App/                 启动、会话状态与 Keychain
JavStrm/Features/            连接、媒体库、发现、详情、订阅、任务和管理页面
JavStrm/UI/                  组件、封面加载、隐私遮罩
JavStrm/Resources/           图标、Info.plist、隐私清单
Sources/JavStrmCore/         可独立编译的接口模型、网络客户端和 SSE 解析
Tests/JavStrmCoreTests/      不依赖测试框架的验证程序及后端接口样本
scripts/                    工程和图标生成、验证入口
docs/                       接口对应关系、真机验收项与验证记录
```

工程通过本地 Swift Package 引用 `JavStrmCore`，不需要下载依赖。添加或移除 App 源码文件后，可以运行：

```bash
python3 scripts/generate_project.py
```

这个命令会重新生成工程的构建配置；它会覆盖在 Xcode 中手动修改的 Team、Bundle ID 等工程设置，之后需重新设置。重新生成品牌图标：

```bash
swift scripts/generate_icon.swift
```

## 验证

只安装 Command Line Tools 也可以运行核心验证：

```bash
bash scripts/verify.sh
```

验证程序使用模拟 HTTP 响应和后端仓库中的固定接口样本，不向真实服务创建任务、不下载资源、不修改服务器。

检查一个实际部署地址，只读取公开的登录配置接口：

```bash
swift run JavStrmVerification --probe http://你的服务器:端口
```

在完整 Xcode 环境执行 iOS 模拟器构建：

```bash
xcodebuild \
  -project JavStrm.xcodeproj \
  -scheme JavStrm \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

**当前验证边界：** 本次原生管理变更完成辅助 Swift 语法、工程引用及资源格式检查，并补充模拟请求回归用例；当前环境缺少 Xcode / Command Line Tools，新增用例和 iOS 构建尚未执行。历史核心验证和公开接口探测记录见 `docs/VALIDATION.md`，不能将历史结果或公开接口探测当作本次编译与登录联调结果。

## 生成 IPA

### GitHub Actions 构建未签名 IPA

仓库包含 `.github/workflows/build-unsigned-ipa.yml`，使用 GitHub 托管的 macOS 环境和 Xcode 16.4，复用本地构建与检查脚本，不需要 Apple 开发者账号、签名证书或 Secrets。

1. 将完整项目（包括 Xcode 工程、源码、资源、`scripts/` 和 `.github/`）推送到 GitHub 仓库。当前 `origin` 指向 Gitea，仅推送到该远程不会运行 GitHub Actions。
2. 在 GitHub 仓库的 **Actions → Build unsigned IPA → Run workflow** 中选择分支并运行。手动运行入口需要工作流已存在于仓库默认分支。
3. 推送到 `main` / `master` 分支，或推送 `v*` 标签（例如 `v1.0.0`），也会自动触发构建。
4. 构建成功后，在仓库的 **Releases** 页面直接下载 `JavStrm-unsigned.ipa` 和同名 JSON 检查报告。运行页面的摘要也会提供 Release 链接；**Artifacts** 中仍保留 `JavStrm-unsigned-ipa-运行编号` 下载入口。

推送 `v*` 标签或手动选择标签构建时，产物上传到同名 Release；如果该 Release 不存在，工作流会自动创建。分支推送和在分支上手动构建时，每次运行创建 `ci-运行编号` 预发布版本，并将标签指向本次构建的提交。重新运行同一次工作流会更新原 Release 的同名附件。

发布使用自动提供的 `GITHUB_TOKEN`，工作流已为构建任务声明 `contents: write` 权限，无需额外配置 PAT。

Actions Artifacts 中的产物保留 14 天；Release 附件不受此保留期限制。Archive 构建日志另存为 `JavStrm-build-logs-运行编号`，构建失败时也会尝试上传已生成的日志。工作流先执行核心与工程验证，再构建 Release 配置的 iPhoneOS arm64 包并检查 IPA 容器、设备平台和签名材料。

未签名 IPA 需要自行签名后才能在普通 iPhone / iPad 上安装。

### 本地构建

安装完整 Xcode 并完成首次运行设置、iOS 平台组件安装后，可构建设备用的未签名包：

```bash
bash scripts/build_ipa.sh unsigned
```

产物写入 `build/ipa-日期时间/JavStrm-unsigned.ipa`，同时保留设备 Archive、构建日志和 JSON 检查报告。未签名包需要完成签名后才能在普通 iPhone 上安装。

若 Xcode 已登录开发者账号，且账号具有有效的签名证书及设备描述文件，可导出签名包：

```bash
JAVSTRM_DEVELOPMENT_TEAM=你的TeamID bash scripts/build_ipa.sh signed
```

该模式使用自动签名和 `debugging` 导出方式，可通过 `JAVSTRM_EXPORT_METHOD` 配置其他 Xcode 支持的导出方式。是否可安装取决于相应证书、描述文件和目标设备。脚本不保存 Apple 账户密码。

单独检查 IPA 容器和设备构建元数据：

```bash
python3 scripts/inspect_ipa.py build/ipa-日期时间/JavStrm-unsigned.ipa --expect-unsigned
```

## 会话与网络

原生请求采用独立的临时 URLSession，不与其他服务共享 Cookie，不把 API 响应和图片落到 URLCache。只持久化 `miyabi_token` 登录 Cookie；该名称由现有后端协议决定，与 App 名称无关。

接口返回 `401 + AUTH_REQUIRED` 才会清除 App 登录状态。115 自身登录失效等业务 `401` 仅显示相应错误。跨源的原生 HTTP 重定向被拒绝，避免向其他服务器发送会话。管理功能通过同一原生 API 会话访问服务器。

后台停止实时同步，返回前台恢复 SSE 并重新获取离线及 STRM 任务。SSE 使用空行边界解析，支持多行数据、心跳和重连快照。接口列表支持 `null` 空集合，未知任务类型仍可以显示。

为兼容用户配置的 HTTP IP 地址，Info.plist 使用 `NSAllowsArbitraryLoads`；仍使用系统正常的 HTTPS 证书校验，不接受任意自签名证书。`NSLocalNetworkUsageDescription` 说明本地网络用途。隐私清单声明本机偏好设置所需的 UserDefaults API 用途。

## 来源

协议以用户提供的 `sean/JavStrm` 仓库为准，基线提交见 `docs/VALIDATION.md`。接口样本来自该仓库 `internal/api/testdata/golden`；应用图标沿用其 `web/public/favicon.svg` 的 J 字母与播放标记。包含对应 GPL-3.0 许可证，详见 `LICENSE` 和 `THIRD_PARTY_NOTICES.md`。
