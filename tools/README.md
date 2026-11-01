# 测试小工具

开发版（`scripts/build.sh`，bundle id `com.wquguru.cicada.dev`）默认就接受这些调试命令，日志在 `/tmp/livesubs-dev-debug.log`。
正式版需要先打开调试模式：`defaults write com.wquguru.cicada debug -bool true`，然后重启 App；日志在 `/tmp/livesubs-debug.log`。

编译：`swiftc -O lsctl.swift -o lsctl`（其他几个文件同理）。

- `lsctl <命令>`：通过分布式通知 `com.wquguru.cicada.debug` 遥控 App。
  - 开关字幕：`start` / `stop`
  - 打开界面：`open`（主窗口）、`panel`（菜单栏面板）、`settings`（设置）
  - 字幕条：`frame` 把位置写进日志，`place:x,y,宽,字号` 摆到指定位置
  - 说话同传：`speakOn` / `speakOff` 开关，`speakFile:<音频>` 把文件当作麦克风输入，`speakOut:<路径>` 把译文语音另存一份
  - 导出：`export:<目录>`
- `mouse move|drag|dclick ...`：模拟鼠标移动、拖动、双击，坐标原点在主屏左下角。
- `key`：模拟按住 ⌥ Space 1.5 秒。
- `toggle-key`：模拟按一下 ⌃⌥S。
- `winall <pid>`：列出某个进程的窗口 ID，配合 `screencapture -l <ID>` 截图。
- `transcribe <音频> <locale>`：用本机模型转写一个文件，用来核对输出。


