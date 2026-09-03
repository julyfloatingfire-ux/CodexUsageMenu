# CodexUsageMenu

一个原生 macOS 用量悬浮窗：在桌面版 Codex 运行时，显示 5 小时和一周的剩余用量。

## 安装

1. 在 [Releases](https://github.com/julyfloatingfire-ux/CodexUsageMenu/releases) 下载最新的 `CodexUsageMenu-*.zip`。
2. 双击解压，得到 `CodexUsageMenu.app`。
3. 将 App 移到“应用程序”文件夹（可选），然后双击打开。

首次打开时，macOS 可能提示无法验证开发者。请在 Finder 中按住 Control 键点按 App，选择“打开”；或前往“系统设置 → 隐私与安全性”允许打开。

## 使用方式

- 启动桌面版 Codex 后，屏幕上会自动出现一个可拖动的圆角正方形；退出 Codex 后它自动隐藏。
- 方框显示 5 小时剩余百分比和恢复时间，以及一周剩余百分比。
- 一周部分的两条蓝色进度条依次表示：一周总额度剩余比例、本周刷新周期的剩余时间比例。
- 按住并拖动方框可以移动位置；普通短按不会移动。
- 短按方框后，会显示“取消置顶”或“置顶”和“退出”两个按钮。
  - 默认置顶；选择“取消置顶”后，其他新窗口可以覆盖方框。
  - 选择“置顶”可恢复始终显示在普通窗口上方。
  - 选择“退出”关闭本应用；点击按钮以外的位置取消该操作层。

方框位置和置顶偏好会在下次启动时保留。

## 自动更新与故障排除

应用启动时会读取 Codex 用量，Codex 推送新用量时会同步，并每分钟复查一次。

如果显示“读取中”较久：确认桌面版 Codex 已启动，并稍等片刻让用量服务完成连接。若旧版本无法退出，可在“活动监视器”中搜索 `CodexUsageMenu` 后强制退出，或在终端执行：

```bash
pkill -x CodexUsageMenu
```

## 开发

源码可直接用 Xcode 打开 `Package.swift`。本项目使用 Swift Package Manager，最低支持 macOS 13。
