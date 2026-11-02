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
- `mouse move|drag|dclick|click|scroll ...`：模拟鼠标移动、拖动、双击、单击、滚轮（`scroll x y 行数`，正数往上翻），坐标原点在主屏左下角。
- `key`：模拟按住说话键。`key right [秒]` 单按右 ⌥；`key <keyCode> <Carbon 修饰键> [秒]` 按组合键（如 `key 122 0` 是 F1）；不带参数是 ⌥ Space。
- `toggle-key`：模拟按一下 ⌃⌥S。
- `winall <pid>`：列出某个进程的窗口 ID，配合 `screencapture -l <ID>` 截图。
- `transcribe <音频> <locale>`：用本机模型转写一个文件，用来核对输出。


