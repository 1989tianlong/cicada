# 复刻说明（Replica Notes）

本仓库是 [wquguru/cicada](https://github.com/wquguru/cicada)（版本 1.5.1，2026-11-08 快照）的复刻，
基于 **Apache-2.0** 协议发布，完整保留上游 LICENSE 与 git 提交历史。原项目作者：[@wquguru](https://x.com/wquguru)。

## 本仓库相对上游的修改

按 Apache-2.0 第 4(b) 条要求声明，全部改动如下（上游身份字符串 `wquguru` 仅在下列位置替换为本仓库标识 `1989tianlong`）：

| 文件 | 改动 |
|---|---|
| `Resources/Info.plist` | Bundle ID `com.wquguru.cicada` → `com.1989tianlong.cicada` |
| `scripts/build.sh` / `scripts/package.sh` | dev/正式 Bundle ID 及校验同步更新 |
| `ios/Resources/Info.plist`、`ios/LiveActivity/Info.plist`、`ios/scripts/build.sh` | iOS Bundle ID 同步更新 |
| `Sources/Cicada/UpdateChecker.swift` | 更新检查与仓库链接指向 `1989tianlong/cicada` 的 Releases |
| `scripts/site.py` | 官网下载/仓库链接指向 `1989tianlong/cicada` |
| `site/i18n/*.json`（4 个） | 隐私说明链接指向本仓库 README |
| `README.md` / `README.en.md` / `README.ja.md` / `README.ko.md` | 顶部增加复刻署名 |
| `Sources/Cicada/AICheck.swift` | 拆分 `summary` 的长链式表达式，修复 Xcode 26.3 下「type-check in reasonable time」编译错误（行为不变） |
| `Tests/CicadaTests/SpeakerTests.swift`、`Tests/CicadaTests/NotesTests.swift` | 同因（Xcode 26.3 类型检查/推断更严格）的测试表达式拆分与字面量显式化，测试逻辑不变 |
| `scripts/deploy-site-aliyun.sh` | 新增：官网一键部署到阿里云 OSS 静态托管 |
| `scripts/device-project.yml`、`scripts/make-device-project.sh` | 新增：用 xcodegen 生成临时 iOS 真机工程（build/device/，不提交），供在 Xcode 里真机安装；上游用纯脚本构建，本仓库保留该机制，真机安装走 Xcode 自动签名 |
| 本文 | 新增 |

## 有意保留、未修改的部分

- **应用名与图标**：仍为「知了 Cicada」，未改名（如需改名另行处理）。
- **分享服务默认地址**（`Sources/Cicada/ShareClient.swift`）：仍指向原服务的 `https://cicada.indaloop.app`，分享功能开箱即用；可用 `defaults write com.1989tianlong.cicada shareServer <url>` 覆盖。
- **GCD 队列标签、聚合音频设备 UID 前缀、调试通知名**（`Sources/Cicada/SystemAudioTap.swift`、`DevBuild.swift`、`tools/lsctl.swift` 等）：`com.wquguru.cicada.*` 字符串为内部自洽标识（发送方与监听方成对出现），改动无收益且有回归风险，保留原样。
- **官网页脚的作者 X 联系方式**：保留指向原作者 @wquguru（署名）。
- **Android / Windows / Linux**：Bundle ID 与链接保持上游原样（本仓库暂不构建这三个平台）。

## 构建与部署

- Mac 版：`scripts/build.sh`（开发版）/ `RELEASE=1 scripts/package.sh`（DMG/zip/校验值）
- iOS 模拟器：`ios/scripts/build.sh`；真机安装：`scripts/make-device-project.sh` → Xcode 打开 `build/device/Cicada.xcodeproj` → Run（或 `xcodebuild CODE_SIGNING_ALLOWED=NO` + `scripts/sign-device.sh <udid>` 用本机通配符 profile 手动签名，无需登录 Xcode 账号；团队 ID 为证书实际所属 `BA7A52F58S`）
- 官网：`python3 scripts/site.py` → `build/site/`；阿里云部署脚本 `scripts/deploy-site-aliyun.sh`

## 线上部署状态（2026-11-08）

- **GitHub**：https://github.com/1989tianlong/cicada （main），Release **v1.5.1** 已发布，含 Mac DMG/zip、Windows、Linux 安装包（Android APK 需先配置 keystore secret，见 `android/scripts/keystore.sh --github`）
- **官网**：阿里云 OSS `cicada-site-1989tianlong`（cn-hangzhou，静态网站托管）
  - 默认端点：https://cicada-site-1989tianlong.oss-cn-hangzhou.aliyuncs.com/index.html
  - 自定义域名：`zhiliao.omniquest.fun`（DNS 在火山引擎，CNAME 已加；绑定 Status: Enabled，2026-11-08 验证 HTTP 200）
  - HTTPS：自定义域名尚未挂证书（OSS 证书需上传或用 CDN 免费证书），先用 HTTP 访问
- **分享后端**：保留上游 Cloudflare Worker（`server/`），未迁移阿里云
