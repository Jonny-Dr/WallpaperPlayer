# 动态壁纸（DynamicWallpaper）

原生 macOS 菜单栏壁纸播放器，零依赖、纯 Swift 编写。

## 支持格式

| 类型 | 说明 |
|---|---|
| 图片 | JPG / JPEG / PNG / WebP / HEIC / GIF / TIFF / BMP |
| 视频 | MP4 / MOV / M4V（无缝循环、静音可切换） |
| Wallpaper Engine 壁纸目录 | 含 `project.json` 的文件夹：`video`、`web`（index.html）、`scene`（用预览图兜底） |

## 使用方法

1. 双击 `DynamicWallpaper.app` 启动，屏幕右上角菜单栏会出现「桌面电脑」图标。
2. 点击菜单栏图标 →「打开图片 / 视频…」或「打开 Wallpaper Engine 壁纸文件夹…」。
3. 也可以在访达里右键任意图片/视频/壁纸文件夹 →「打开方式」→「动态壁纸」。
4. 菜单功能：暂停/继续、声音、显示方式（填充裁切 / 完整显示黑边）、开机启动、恢复系统壁纸、退出。
5. 壁纸会记住上次选择，重启自动恢复。

## 实现要点

- 壁纸窗口层级：桌面壁纸之上（-2147483626）、桌面图标之下（-2147483603），位于 `kCGDesktopWindowLevel`。
- 视频使用共享 `AVPlayer` + 每屏一个 `AVPlayerLayer`，播完自动 seek 到 0 循环。
- 窗口 `canJoinAllSpaces + stationary`，全屏应用和多桌面切换时保持显示。
- WE `scene` 类型的 `scene.pkg` 是专有格式无法渲染，自动回退到 `preview.*` 预览图。

## 构建

```bash
swiftc -O -swift-version 5 -module-cache-path .modcache \
  main.swift WallpaperLoader.swift WallpaperController.swift AppDelegate.swift \
  -o DynamicWallpaper.app/Contents/MacOS/DynamicWallpaper
cp Info.plist DynamicWallpaper.app/Contents/
codesign --force --sign - DynamicWallpaper.app
```

## 日志

播放日志：`~/Library/Logs/DynamicWallpaper.log`
