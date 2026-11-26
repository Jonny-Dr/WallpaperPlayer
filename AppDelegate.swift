import AppKit
import UniformTypeIdentifiers
import ServiceManagement

/// 菜单栏 App：选择壁纸、控制播放、开机自启
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let controller = WallpaperController()
    private let defaults = UserDefaults.standard

    private var titleItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var soundItem: NSMenuItem!
    private var fillItem: NSMenuItem!
    private var fitItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "动态壁纸")
            btn.toolTip = "动态壁纸"
        }
        statusItem.menu = buildMenu()

        // 恢复上次使用的壁纸
        if let path = defaults.string(forKey: "wallpaperPath"),
           let content = WallpaperLoader.load(path: path) {
            controller.show(content)
            updateTitle(content.name)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls {
            if let c = WallpaperLoader.load(path: u.path) {
                activate(c, sourcePath: u.path)
                return
            }
        }
    }

    // MARK: - 菜单

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        titleItem = NSMenuItem(title: "未选择壁纸", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("打开图片 / 视频…", #selector(openFile)))
        menu.addItem(makeItem("打开 Wallpaper Engine 壁纸文件夹…", #selector(openFolder)))
        menu.addItem(.separator())

        pauseItem = makeItem("暂停播放", #selector(togglePause))
        pauseItem.isEnabled = false
        menu.addItem(pauseItem)

        soundItem = makeItem("声音", #selector(toggleSound))
        soundItem.isEnabled = false
        soundItem.state = controller.isMuted ? .off : .on
        menu.addItem(soundItem)
        menu.addItem(.separator())

        let fitMenu = NSMenu()
        fitMenu.autoenablesItems = false
        fillItem = NSMenuItem(title: "填充（裁切）", action: #selector(selectFill), keyEquivalent: "")
        fitItem = NSMenuItem(title: "完整显示（黑边）", action: #selector(selectFit), keyEquivalent: "")
        fillItem.target = self
        fitItem.target = self
        fillItem.state = controller.fitMode == .fill ? .on : .off
        fitItem.state = controller.fitMode == .fit ? .on : .off
        fitMenu.addItem(fillItem)
        fitMenu.addItem(fitItem)
        let fitRoot = NSMenuItem(title: "显示方式", action: nil, keyEquivalent: "")
        fitRoot.submenu = fitMenu
        menu.addItem(fitRoot)

        loginItem = makeItem("开机启动", #selector(toggleLogin))
        loginItem.state = loginEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("恢复系统壁纸", #selector(clearWallpaper)))
        menu.addItem(makeItem("退出", #selector(quit)))

        return menu
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.isEnabled = true
        return it
    }

    private func updateTitle(_ name: String) {
        titleItem.title = "当前：\(name)"
        let video = controller.current?.isVideo ?? false
        let dynamic = video || (controller.current?.isWeb ?? false)
        pauseItem.isEnabled = video
        pauseItem.title = controller.isPaused ? "继续播放" : "暂停播放"
        soundItem.isEnabled = dynamic
        soundItem.state = controller.isMuted ? .off : .on
        fillItem.state = controller.fitMode == .fill ? .on : .off
        fitItem.state = controller.fitMode == .fit ? .on : .off
    }

    // MARK: - 打开壁纸

    @objc private func openFile() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowedContentTypes = [.image, .movie]
        p.message = "选择图片（JPG / PNG / WebP）或视频（MP4 / MOV）"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        activatePath(url.path)
    }

    @objc private func openFolder() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowedContentTypes = [.folder]
        p.message = "选择含 project.json 的 Wallpaper Engine 壁纸文件夹"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        activatePath(url.path)
    }

    private func activatePath(_ path: String) {
        guard let c = WallpaperLoader.load(path: path) else {
            let a = NSAlert()
            a.messageText = "无法识别的壁纸"
            a.informativeText = "支持 JPG / PNG / WebP 图片、MP4 / MOV 视频，以及含 project.json 的 WE 壁纸文件夹。\n路径：\(path)"
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
            return
        }
        activate(c, sourcePath: path)
    }

    private func activate(_ content: WallpaperContent, sourcePath: String) {
        controller.show(content)
        defaults.set(sourcePath, forKey: "wallpaperPath")
        updateTitle(content.name)
    }

    // MARK: - 控制

    @objc private func togglePause() {
        let paused = controller.togglePause()
        pauseItem.title = paused ? "继续播放" : "暂停播放"
    }

    @objc private func toggleSound() {
        controller.isMuted.toggle()
        soundItem.state = controller.isMuted ? .off : .on
    }

    @objc private func selectFill() {
        controller.setFitMode(.fill)
        fillItem.state = .on
        fitItem.state = .off
    }

    @objc private func selectFit() {
        controller.setFitMode(.fit)
        fitItem.state = .on
        fillItem.state = .off
    }

    @objc private func clearWallpaper() {
        controller.clear()
        defaults.removeObject(forKey: "wallpaperPath")
        updateTitle("")
        titleItem.title = "未选择壁纸"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 开机启动

    private var loginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        let svc = SMAppService.mainApp
        if svc.status == .enabled {
            try? svc.unregister()
        } else {
            do {
                try svc.register()
            } catch {
                let a = NSAlert()
                a.messageText = "无法设置开机启动"
                a.informativeText = error.localizedDescription
                NSApp.activate(ignoringOtherApps: true)
                a.runModal()
            }
        }
        loginItem.state = loginEnabled ? .on : .off
    }
}
