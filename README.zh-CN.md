<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="知了图标">
</p>

<h1 align="center">知了 · Cicada</h1>

<p align="center">
  任何会议、任何直播，没有语言障碍。<br>
  听得懂，说得出，记得住。Mac 上的实时纪要、双语文字记录、字幕与同声传译。
</p>

<p align="center">
  <a href="https://cicada.indaloop.app"><img src="https://img.shields.io/badge/官网-cicada.indaloop.app-E8552B?style=for-the-badge" alt="官网 cicada.indaloop.app" height="36"></a>
  &nbsp;
  <a href="https://github.com/wquguru/cicada/releases/latest"><img src="https://img.shields.io/badge/下载-macOS 版-15171C?style=for-the-badge&logo=apple&logoColor=white" alt="下载 macOS 版" height="36"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-black" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Apple%20silicon-only-black" alt="Apple 芯片">
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a></p>

<p align="center">
  <a href="docs/demo.mp4"><img src="docs/demo.gif" width="800" alt="英文会议进行时，知了左边写中文纪要，右边是逐句双语文字记录"></a>
</p>
<p align="center"><a href="docs/demo.mp4">▶ 看 52 秒完整演示（有声音）</a></p>

知了（Cicada，原名 Live Subs）是一个常驻 Mac 菜单栏的工具，直接听电脑正在播放的声音。像上面视频里那样，开英文产品会时，左边窗口边听边整理中文纪要，右边同步滚动逐句的英中双语文字记录。它不需要派机器人进会，对方也不用装任何东西。平时看直播、看视频或者进语音房，你还可以切到轻巧的字幕条，或者按住快捷键说话，让对方直接听到翻译后的语音。

## 主要功能

### 实时纪要与双语文字记录

- **边开会边写纪要**。悬浮窗口大约每 45 秒更新一次，自动整理出会议总结、最多 8 个议题和对应要点、讨论原因时的鱼骨图、结论和待办，以及人名术语表。要点和结论带有时间，议题带有时间段。会议结束后还会再整理出一份完整版。纪要默认用你的语言（系统语言里有中文就用中文），也可以改用会议原文，实时版和完整版始终一致。
- **结论随时跳回原话**。每条结论和待办都会标出背后有几句原话支持，点一下就能直接跳到文字记录里的那句话。
- **逐句双语对照**。右边文字记录把每句话的原文和译文上下排在一起，正在说的那半句也会实时显示。往上翻看前面的内容时不会被新句子拉回底部，新内容会攒成一个“↓ N 句新内容”按钮。
- **认得准人名和术语**。纪要会统一文中人名和术语的写法，并记下语音识别听错的写法。按 `⌘F` 搜索时，连同识别错的写法也能一起搜出来。
- **窗口形态随手调**。把窗口拉宽到 760 点以上，纪要和文字记录就会并排显示。缩窄后变成一张小卡片，收起期间如果有人说了新内容，卡片上会提示“收起后新增 …”。共享屏幕和截图时别人完全看不到这个窗口，鼠标点它也不会把焦点从会议软件里抢走。

### 实时字幕与语言识别

- **半秒内自动判断语言**。所有已安装的本机语音模型会同时听同一段声音，最有把握的那个胜出。语音识别由 Apple SpeechAnalyzer（苹果本机语音识别框架）在本地完成。
- **自动翻成你的语言**。默认跟随系统语言，如果对方说的正好是你的第一系统语言，就自动翻成你的下一个系统语言，也可以随时手动指定。设置 › 语言 用一行看清整条路线，字幕可以双语、只看译文或只看原文（只看原文时不翻译）；纪要窗口的「EN → 中」可以只改这一场。
- **不挡操作的字幕条**。按 `⌃⌥S` 可以在实时纪要窗口、字幕条、不显示三者之间切换。字幕条只有在有人说话时才出现，安静下来就收成一个小圆点。鼠标划过时字幕条会变透明，底下的按钮照样能点。鼠标停在上面 0.6 秒就能拖动或缩放，双击恢复默认大小，每块屏幕各记各的位置和大小。

### 同声传译（说话也能翻译）

- **按住快捷键说话**。按住键盘右边的 `⌥` 键开口（可以在设置里改成别的组合键），对方听到的就是翻译后的语音。声音通过 BlackHole 2ch（虚拟音频驱动）传给会议软件，在知了里点一下就能从官方下载安装并自动试音。
- **自然人声与声音克隆**。填了 Ling（蚂蚁集团的大模型服务）的 API key 后，会由 Ming 语音模型一步听懂并翻译你说的话，大约 2 秒出声，人名翻译得更准。对方听到的声音可以选 Ming 的自然人声（英文有 Emma、George、Charlotte，中文有小雅、小棠、小锋、卓然，另外还有日、韩、德、法、西语）、Mac 自带语音，或者录一段 8 到 30 秒自己的声音做克隆。不填 key 时则使用 Mac 自带语音。
- **会前试一句**。“设置”里的“试一句”会把一句话走完整个流程送进虚拟麦克风，再把对方收到的原样声音放给你听。同时显示每一步的耗时，自动检查对方听不听得到、听不听得懂。

### 会议记录

- **完整保存在本机**。每场会议单独建一个文件夹，存下双语文字记录、纪要和原始录音。说话人目前区分“对方”和“你”，还不能细分对方是哪几位。
- **多格式导出**。支持导出成 Markdown、Word（这两种格式开头就是整理好的纪要）以及 SRT 字幕文件。如果开会时没开实时纪要，会后随时可以点“生成纪要”补一份。

<p align="center">
  <img src="docs/panel.png" width="300" alt="菜单栏面板">
  &nbsp;
  <img src="docs/meetings.png" width="520" alt="会议记录：每句话都有原文和译文">
</p>

## 费用与隐私

声音采集、语言识别、语音识别（Apple SpeechAnalyzer）和会议录音全部在本机完成，录音文件只存在你自己的硬盘里。会离开电脑的数据只有识别出来的文字（发去做翻译和生成纪要），以及填了 Ling API key 并按住说话键用同声传译时，你按住按键说的那几句语音。另外，知了每天会向 GitHub 查一次最新版本，请求里不带任何关于你或会议的内容。

不填 API key 的情况下，实时字幕、翻译、会议记录和同声传译都能正常用，此时翻译默认走 Google，连不上时退回 Apple 本机翻译。

实时纪要、更准确的翻译、一步语音翻译和声音克隆需要用到你自己的 Ling API key（蚂蚁集团的大模型服务，官网 `ant-ling.com`，配置方法见[下文](#配置-ling-api-key)）。这个 key 只存在本机一个只有当前系统账户能读的文件里，不会进入备份。生成纪要只发送识别出的文字，按目前的价格，开一小时会大约花 0.15 到 1 元人民币。

## 用到的模型

不填 Ling key 时，全部由 Apple 本机模型加 Google 翻译完成。填了 key 后，下表中的部分改由 Ling 和 Ming 模型负责，任何一步失败都会自动退回下一级。

| 功能 | 填了 Ling key | 不填 key / 退回 |
|---|---|---|
| 语音识别、语言识别 | Apple `SpeechAnalyzer` / `SpeechTranscriber`（本机） | 同左 |
| 整句翻译 | Ling `Ling-3.1-flash`（可在“设置 › AI 服务”改为 `Ling-3.0-flash`） | Google 翻译 → Apple `Translation`（本机） |
| 正在说的半句话的翻译 | Google 翻译（不占 Ling 的频率额度） | Apple `Translation`（本机） |
| 实时纪要、会后完整版 | Ling `Ling-3.1-flash`（同上设置） | 不可用 |
| 检查 key 是否有效 | Ling `Ling-3.0-tiny`（只用一个 token） | — |
| 同声传译：听懂并翻译你说的话 | Ming `Ming-3.0-audio-flash`，一步完成 | Apple 本机识别，再走上面的翻译链 |
| 同声传译：对方听到的声音、声音克隆 | Ming `Ming-3.0-tts-0.5B` | Mac 自带语音（`AVSpeechSynthesizer`），不能克隆 |

## 配置 Ling API key

1. 打开 [Ling 开放平台](https://chat.ant-ling.com/platform/api)，注册或登录。
2. 点“创建令牌”，复制以 `sk-` 开头的那串 key。
3. 在知了里打开“设置 › AI 服务”，粘贴后点“保存并检查”（也可以直接粘贴到纪要窗口顶部的提示框里）。知了会发一个只用一个 token 的请求确认 key 可用。
4. 同一页面可以选模型（默认 `Ling-3.1-flash`），每种语言用哪个 Ming 声音在“设置 › 同声传译”里选。

想移除 key，在同一页面点“移除”即可。

## 系统要求与安装

需要搭载 Apple 芯片的 Mac，系统版本 macOS 26 或更新版本。

1. 去 [Releases 页面](https://github.com/wquguru/cicada/releases/latest) 或 [知了官网 cicada.indaloop.app](https://cicada.indaloop.app) 下载 `Cicada-<版本>-macOS-AppleSilicon.dmg`。下载页旁边同时提供 `.zip` 压缩包和 `checksums.txt`（SHA-256 校验值）。
2. 打开 DMG，把知了拖进“应用程序”文件夹。
3. 因为应用采用本地签名（ad-hoc），没有走苹果公证，第一次打开会被系统拦下。请打开系统的“系统设置 › 隐私与安全性”，滑到底部点“仍要打开”。

以后的新版本在应用里就能更新：有新版本时菜单栏图标上会出现一个橙点，点一下即可下载、按 SHA-256 校验、替换并重新打开，权限不丢。想开机后让知了在菜单栏待命，打开“设置 › 通用 › 登录时打开”。

首次打开时有简单的三步引导，先开启“听电脑里的声音”权限（麦克风权限可选），接着播放内置示例视频马上看到实时字幕跳出来，最后如果想让对方听到翻译，点一下就能安装虚拟麦克风（需要输一次电脑的管理员密码）并自动试音。

## 使用方法

界面有中文、英文、日文和韩文，跟随 macOS 的系统语言（也可以在“系统设置 › 通用 › 语言与地区”里单独给知了指定）。

1. 放任何有声音的视频、直播或会议，默认会弹出实时纪要窗口。随时按 `⌃⌥S` 可以在实时纪要窗口、字幕条和不显示之间切换（快捷键可在设置里改）。
2. 点菜单栏上的知了图标，可以调整听到的语言（默认自动识别）、翻译成的语言以及显示方式。
3. 想用实时纪要的话，去 [Ling 开放平台](https://chat.ant-ling.com/platform/api) 申请一个 API key，填进“设置 › AI 服务”或纪要窗口的提示框里。
4. 想用同声传译跟对方说话，在菜单栏面板里打开同声传译，去会议软件里把麦克风设备选成 BlackHole 2ch，然后按住右边的 `⌥` 键开口（第一次按会提示开启系统的“输入监控”权限）。
5. 点面板里的“会议记录”可以翻看以前的纪要和双语文字记录，支持 `⌘F` 搜索、补生成纪要，或者导出成 Markdown、Word 和 SRT 字幕。

## 卸载

退出知了，去“应用程序”里把它拖进废纸篓即可。

平时存下的会议记录和录音都在 `~/Library/Application Support/LiveSubs` 文件夹里，不需要的话可以手动删掉。如果想彻底清除软件设置，可以在终端运行下面这行命令。

```bash
defaults delete com.wquguru.cicada
```

## 开发

从源码构建只需要安装 Xcode Command Line Tools（`xcode-select --install`）。项目没有任何第三方依赖，只调用 macOS 系统原生框架。

```bash
scripts/build.sh            # 编译开发版 → build/Cicada.app（名为“Cicada Dev”，可与正式版同时运行）
open build/Cicada.app
scripts/package.sh          # 打包正式版 DMG、zip 和 SHA-256 校验值
```

代码架构等说明写在 [AGENTS.md](AGENTS.md) 里。官网源码放在 `site/` 目录，由 `scripts/site.py` 生成。历次更新记录可以看仓库里的 [CHANGELOG.md](CHANGELOG.md)，或者看官网的 [更新日志页](https://cicada.indaloop.app/changelog/)。

## 开源协议

本项目采用 [Apache-2.0](LICENSE) 协议开源。同声传译用到的虚拟麦克风驱动 BlackHole 2ch 采用 GPL 协议，知了安装包里不打包它，而是在你点安装时直接从它的官方发布地址下载。
