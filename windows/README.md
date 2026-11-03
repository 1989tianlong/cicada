# 知了 Windows 版

Cicada 的 Windows 版，目前只做“听”：把电脑播放的声音变成双语字幕和实时纪要，存成和 Mac 版同一格式的会议记录。方案和取舍见 [docs/windows-plan.md](../docs/windows-plan.md)。

- 抓声音：WASAPI 进程回环，排除知了自己（Windows 10 2004 起）。
- 识别：Ming（`Ming-3.0-audio-flash`）分段识别，一次请求同时返回语言、原文和译文；需要 Ling key。
- 纪要、记录格式、提示词、多语言文案都和 Mac 版一致；文案的英日韩翻译直接用 `Resources/*.lproj/Localizable.strings`，Windows 独有的在 `src/Cicada/Strings/`。

## 目录

| 路径 | 内容 |
|---|---|
| `src/Cicada.Core` | 不依赖界面的引擎（`net10.0`，Mac 上也能编译、运行、测试） |
| `src/Cicada` | Windows 应用：托盘、纪要窗 / 字幕条、会议记录、设置、引导（WPF，代码写界面，不用 XAML） |
| `src/Cicada.Cli` | 在 Mac 上用 WAV 文件跑完整流程、检查会议记录 |
| `tests/Cicada.Tests` | 单元测试（控制台程序，不用测试框架） |
| `spike/` | M0 验证：`ming_asr.py`、`LoopbackProbe` |

## 命令（在 Mac 上）

```bash
scripts/install-dotnet.sh          # 一次：.NET 10 SDK 装到 ~/.dotnet，不用 sudo
scripts/test.sh                    # 单元测试
scripts/build.sh                   # 开发版：build/Cicada-win-x64/、build/Cicada-win-arm64/
RELEASE=1 scripts/build.sh         # 发布版
python3 scripts/strings.py         # 查缺翻译的文案（--write 追加 TODO）
```

不依赖 Windows 的验证：

```bash
DOTNET_ROOT=~/.dotnet build/cli/cicada-cli listen spike/clips/en.wav --target zh-CN --notes   # 真实调用 Ming 和 Ling
DOTNET_ROOT=~/.dotnet build/cli/cicada-cli roundtrip ~/Library/Application\ Support/LiveSubs/Sessions/*/session.json
```

先 `scripts/dotnet.sh build src/Cicada.Cli -o build/cli` 编译命令行工具；它读 Mac 版的 key 文件，不打印 key。

## 在 Windows 里验证

1. 把 `build/Cicada-win-arm64`（ARM 虚拟机）或 `build/Cicada-win-x64`（x64 电脑）拷过去。
2. 先跑抓声音验证：`spike/LoopbackProbe` 编译出的 `LoopbackProbe.exe`，一次默认、一次 `--include-self`，前者应显示 `absent`，后者 `PRESENT`。
3. 双击 `Cicada Dev.cmd` 打开开发版（记录在 `%APPDATA%\Cicada Dev`，日志在 `%TEMP%\cicada-dev-debug.log`）。
4. 用 PowerShell 驱动：`scripts\cicadactl.ps1 state`、`start`、`feed C:\path\en.wav`、`view subtitles`、`capture on`、`stop`。
5. 检查：纪要窗不抢焦点（点它之后原来的窗口仍能打字）；Win+Shift+S 截图和会议软件的屏幕共享里看不到它；打开“共享屏幕时让对方看到”后能看到，并显示“对方可见”。
