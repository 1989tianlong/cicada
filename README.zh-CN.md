<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="知了图标">
</p>

<h1 align="center">知了 · Cicada</h1>

<p align="center">
  任何会议、任何直播，没有语言障碍。<br>
  Mac 上的实时字幕、同声传译和 AI 会议纪要：听得懂，说得出，记得住。
</p>

<p align="center">
  <a href="https://github.com/wquguru/cicada/releases/latest"><b>下载 macOS 版</b></a> · <a href="CHANGELOG.md"><b>更新内容</b></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-black" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Apple%20silicon-only-black" alt="Apple 芯片">
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0">
</p>

<p align="center">
  <img src="docs/hero.jpg" width="880" alt="英文直播画面上，知了的字幕条显示中文翻译">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a></p>

---

知了（Cicada，原名 Live Subs）听电脑里正在播放的声音，比如直播、视频、会议或语音房。它先判断说的是哪种语言，再把翻译显示在置顶的小字幕条上。语音识别在本机完成，只有识别出的文字会发去翻译。

## 功能

- **自动识别语言**：所有已安装的本机语音模型同时听同一段声音，最有把握的那个胜出，通常半秒内就能判断出来。
- **翻译成你的语言**：默认跟随系统语言。如果系统是英文、对方说的也是英文，就翻成你的第二首选语言。也可以手动指定。
- **不挡操作**：
  - 有人说话时字幕条才出现，安静后收成一个小点；
  - 鼠标经过时字幕条会变透明，下面的按钮照样能点；
  - 鼠标停住不动，就可以拖动、缩放字幕条；
  - ⌃⌥S 随时隐藏或显示。
- **实时纪要**：在 设置 › AI 服务 填上自己的 [Ling](https://chat.ant-ling.com/open) API key（只存在你的 Mac 上，只有你的账户能读），开会时一个悬浮窗口会边听边整理：总结、议题和要点、讨论原因时的鱼骨图、结论和待办、统一写法的人名。窗口可以拖到任何地方、收成小卡（收起后有新内容时会提示）或拉宽和文字记录并排；共享屏幕时别人看不到它。它开着时，左上角有知了的菜单（停止记录 ⌘R、收起后的新内容 ⌘J、搜索 ⌘F、窗口大小 ⌘1–⌘3）。会议结束后再整理一遍完整版。同一个 key 还让翻译更准；同声传译时对方可以听到自然的 Ming 声音，或者录 15 秒、用你自己的声音（设置 › 同声传译）；没有 key 时其他功能照常。
- **说话也能翻译**：按住右边的 ⌥ 键说话，会议里的人听到的是翻译后的语音。这需要一个虚拟麦克风，在 App 里一键安装。填了 Ling key 时，由 Ming 语音模型一步听懂并翻译，人名更准。
- **会议记录**：每场会议都自动存成双语稿子（录音只存在本机），可以导出 Markdown、Word 或 SRT。
- **隐私**：声音采集、语言识别、语音识别都在本机完成。唯一会离开 Mac 的声音，是填了 Ling key 时你按住说话键说的那几句。

<p align="center">
  <img src="docs/panel.png" width="300" alt="菜单栏面板">
  &nbsp;
  <img src="docs/meetings.png" width="520" alt="会议记录：每句话都有原文和译文">
</p>

<p align="center">
  <img src="docs/onboarding.png" width="520" alt="首次引导：播放内置示例，字幕实时出现">
</p>

## 系统要求

- macOS 26，Apple 芯片
- 从源码构建：Xcode Command Line Tools（`xcode-select --install`）

## 安装

1. 从 [Releases](https://github.com/wquguru/cicada/releases) 下载 **`Cicada-<版本>-macOS-AppleSilicon.dmg`**。旁边还有一个 `.zip` 和 `checksums.txt`（SHA-256 校验值）。
2. 打开 DMG，把 **知了** 拖进「应用程序」。
3. 第一次打开会被系统拦住，因为 App 没有经过公证。去 **系统设置 › 隐私与安全性**，点 **仍要打开**。

第一次打开时有三步引导：

1. 打开「听电脑里的声音」，麦克风可选；
2. 播放内置的示例视频，看字幕出来；
3. 如果想让对方听到你的翻译，一键安装虚拟麦克风（只需要输一次电脑密码），装好后自动试音，确认对方听得到。

## 使用

1. 播放任何有声音的内容，实时纪要窗口里会出现文字记录和字幕行。想要原来的字幕条，在面板里选“字幕条”；⌃⌥S 在实时纪要、字幕条、不显示之间切换。
2. 点菜单栏图标，可以改“听到”的语言（默认自动识别）、“翻译成”的语言，以及显示方式。
3. 想要纪要：在 设置 › AI 服务（或直接在纪要窗口里）填上 Ling 的 API key。按目前价格一小时会议约 ¥0.15–1；纪要发出去的只有文字，听对方说话的识别留在本机。
4. 想让对方听到你的翻译：
   - 打开 **同声传译**；
   - 在会议软件里把麦克风选成 **BlackHole 2ch**；
   - 说话时按住右边的 ⌥ 键（第一次会请你允许“输入监控”）。两个快捷键都能在设置里换。
5. 面板里的 **会议记录** 可以看每场会议的纪要和文字记录：能搜索、导出（Markdown 和 Word 开头就是纪要）。没有纪要的会议可以点“生成纪要”。

### 卸载

退出知了，把它拖进废纸篓即可。会议稿子和录音保存在 `~/Library/Application Support/LiveSubs`，需要的话手动删除。设置可以用 `defaults delete com.wquguru.cicada` 清除。

## 开发

```bash
scripts/build.sh            # 开发版 → build/Cicada.app（“知了 Dev”，可以和正式版同时运行）
open build/Cicada.app
scripts/package.sh          # 正式版 DMG、zip 和校验值
```

架构、开发版和正式版的区别、打包、测试、发布流程，见 [AGENTS.md](AGENTS.md)。

官网（`site/`，发布到 GitHub Pages）由 `scripts/site.py` 生成，见 AGENTS.md。

## 开源协议

[Apache-2.0](LICENSE)。虚拟麦克风 BlackHole 是 GPL 协议，安装时从它的官方发布下载，不随 App 分发。
