# 测试小工具

开发版（`scripts/build.sh`，bundle id `com.wquguru.cicada.dev`）默认就接受这些调试命令，日志在 `/tmp/livesubs-dev-debug.log`。
正式版需要先打开调试模式：`defaults write com.wquguru.cicada debug -bool true`，然后重启 App；日志在 `/tmp/livesubs-debug.log`。

编译：`swiftc -O lsctl.swift -o lsctl`（其他几个文件同理）。

- `lsctl <命令>`：通过分布式通知 `com.wquguru.cicada.debug` 遥控 App。
  - 开关字幕：`start` / `stop`
  - 打开界面：`open`（主窗口）、`panel`（菜单栏面板）、`settings[:speak]`（设置，可指定栏目）
  - 虚拟麦克风：`micTest` 试音（往虚拟麦克风播一句再听回来，结果写进日志），`micNext` 做清单里的下一步
  - 快捷键：`talkKey:right` 或 `talkKey:<keyCode>:<Carbon 修饰键>` 换说话键（被拒的原因写进日志），`toggleKey:…` 同理，`shortcuts` 把当前状态写进日志
  - 字幕条：`frame` 把位置写进日志，`place:x,y,宽,字号` 摆到指定位置
  - 说话同传：`speakOn` / `speakOff` 开关，`speakFile:<音频>` 把文件按实时速度当作麦克风输入，`speakOut:<路径>` 把译文语音另存一份，`speakOutput:<设备名片段>` 改输出设备（留空 = 虚拟麦克风）
  - 试一句：`speakTest:sample`（Mac 读一句示例）或 `speakTest:voice`（再发 `speakTestBegin` / `speakTestEnd` 当作按住、松开），结果以 `speak test:` 写进日志；`speakTestState`、`speakTestRender:<png>`、`speakTestClose`
  - 多开：两边都设 `CICADA_DEBUG_CHANNEL=x`（`open -n --env CICADA_DEBUG_CHANNEL=x build/Cicada.app`），命令只发给这一份，日志在 `/tmp/livesubs-dev-debug-x.log`
  - 导出：`export:<目录>`
  - 新手引导与窗口：`onboarding:<步骤>`、`samplePlay`、`closeWindow:<main|settings|onboarding>`、`settings:<overlay|language|speak|records|ai|diagnostics>`、`about`
  - 显示与字幕：`display:<notes|bar|none>`、`subtitles:<both|translation|original>`、`meetingSubtitles:<…>`、`overlayState`、`overlayToggle`、`overlayAuto[:off]`、`hideAfter:<秒>`
  - 纪要：`notesLang:<mine|source>`、`meetingNotesLang:<…>`、`notesRegenerate:<id>=<mine|source>`、`notesWindow[:x,y,w,h]`、`notesClose`、`notesFrame`、`notesNow`、`notesState`、`notesShow:<id>`、`notesReplay:<id>`、`notesCapturable[:off]`
  - 渲染（不需要录屏权限）：`windowsRender:<目录>`、`settingsRender:<栏目>=<png>`、`notesRender:<png>`、`mainShow:<id>[,transcript]`、`mainRender:<png>`、`speakTestRender:<png>`
  - AI：`aiKeyFile:<路径>`（从 0600 文件读 key，不经过日志；测完就删掉文件）、`aiCheck`、`aiRemove`、`aiState`、`lingSimulate:<429|hijack|timeout|off>`
  - 声音：`voice:<语言>[=<id>]`、`voicePreview:<语言>=<id>`、`voiceCloneFile:<wav>`、`voicePicker:<on|off>`
  - 诊断：`diagnostics:<on|off>`、`diagReport`
  - 更新与登录项：`updateFeed:<url>`、`updateCheck`、`updateInstall`、`updateState`、`loginItem[:on|off]`
  - 完整、最新的清单以 `AppModel.debugCommand` 里的 `switch` 为准。

## 测试技巧

- 英文界面：`defaults write com.wquguru.cicada.dev AppleLanguages -array en` 后重启，测完 `defaults delete com.wquguru.cicada.dev AppleLanguages`；或启动时加 `--args -AppleLanguages "(en)"`。
- 纪要窗口不出现在截屏里：先发 `notesCapturable` 再 `screencapture -l`，或直接 `notesRender:`。
- 合成的按键会发给所有 App：别的 App 的启动器可能抢走 ⌥ Space。模拟鼠标和按键需要终端有“辅助功能”权限。
- 试一句可以测整条同传链路和延迟：`speakTest:sample` 连发几次，读日志里的 `speak test:` 行。
- 端到端测更新：把 `CFBundleShortVersionString` 调高再构建，`ditto -c -k --keepParent build/Cicada.app Cicada-<v>-macOS-AppleSilicon.zip`，`shasum -a 256` 写进 `checksums.txt`，写一个资源地址用 `file://` 的 release JSON，从 scratchpad 运行旧版开发版（不要用 `build/` 里的），再 `updateFeed:file://…` 和 `updateInstall`。
- `mouse move|drag|dclick|click|scroll ...`：模拟鼠标移动、拖动、双击、单击、滚轮（`scroll x y 行数`，正数往上翻），坐标原点在主屏左下角。
- `key`：模拟按住说话键。`key right [秒]` 单按右 ⌥；`key <keyCode> <Carbon 修饰键> [秒]` 按组合键（如 `key 122 0` 是 F1）；不带参数是 ⌥ Space。
- `toggle-key`：模拟按一下 ⌃⌥S。
- `winall <pid>`：列出某个进程的窗口 ID，配合 `screencapture -l <ID>` 截图。
- `transcribe <音频> <locale>`：用本机模型转写一个文件，用来核对输出。


