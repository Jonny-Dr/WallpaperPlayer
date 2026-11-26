import AppKit
import AVFoundation
import WebKit

enum WallpaperFitMode: String {
    case fill   // 填充（裁切）
    case fit    // 完整显示（留黑边）
}

/// 管理所有屏幕上的壁纸窗口：图片 / 视频循环播放 / WE 网页壁纸
final class WallpaperController {

    private(set) var current: WallpaperContent?

    var fitMode: WallpaperFitMode = .fill {
        didSet { applyFitMode() }
    }

    private(set) var isPaused = false

    var isMuted: Bool = true {
        didSet { player.isMuted = isMuted }
    }

    // 桌面层级：位于桌面壁纸之上、桌面图标之下
    private static var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    }

    private let player = AVPlayer()
    private var windows: [NSWindow] = []
    private var videoContainers: [VideoContainerView] = []
    private var imageContainers: [ImageContainerView] = []
    private var loopObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var timeObserver: Any?

    init() {
        player.actionAtItemEnd = .none
        player.isMuted = isMuted

        // 视频播完自动回到开头，无缝循环
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player.seek(to: .zero) { _ in
                if !self.isPaused { self.player.play() }
            }
        }

        // 屏幕分辨率 / 外接显示器变化时重建窗口
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.current != nil else { return }
            self.rebuild()
        }

        // 每 2 秒记录播放进度（用于验证视频确实在循环播放）
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 2, preferredTimescale: 600), queue: .main
        ) { [weak self] t in
            guard let self, self.current?.isVideo == true else { return }
            Self.log("playback t=\(String(format: "%.2f", t.seconds))s paused=\(self.isPaused)")
        }
    }

    // MARK: - 调试日志 / 自截屏

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DynamicWallpaper.log")

    static func log(_ msg: String) {
        let line = "\(Date()) [动态壁纸] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: data)
        } else if let fh = try? FileHandle(forWritingTo: logURL) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
        }
    }

    deinit {
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    // MARK: - 对外操作

    func show(_ content: WallpaperContent) {
        current = content
        isPaused = false
        rebuild()
    }

    func clear() {
        current = nil
        teardown()
    }

    /// 仅对视频有效；返回切换后的暂停状态
    func togglePause() -> Bool {
        guard current?.isVideo == true else { return isPaused }
        isPaused.toggle()
        if isPaused {
            player.pause()
        } else {
            player.play()
        }
        return isPaused
    }

    func setFitMode(_ mode: WallpaperFitMode) {
        fitMode = mode
    }

    // MARK: - 窗口构建

    private func rebuild() {
        teardown()
        guard let content = current else { return }

        if case .video(let url, _) = content {
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            player.isMuted = isMuted
        }

        for screen in NSScreen.screens {
            let container = makeContainer(for: content)
            let w = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            w.level = Self.desktopLevel
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.isMovable = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.contentView = container
            w.orderFront(nil)
            windows.append(w)
        }

        if case .video = content, !isPaused {
            player.play()
        }
        // 强制布局，确保视频图层拿到正确尺寸
        for w in windows { w.contentView?.layoutSubtreeIfNeeded() }
        if let v = videoContainers.first {
            Self.log("show \"\(content.name)\" on \(windows.count) screen(s), level=\(windows.first?.level.rawValue ?? 0), playerLayer.frame=\(v.playerLayer.frame)")
        } else {
            Self.log("show \"\(content.name)\" on \(windows.count) screen(s), level=\(windows.first?.level.rawValue ?? 0)")
        }
    }

    private func teardown() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        for w in windows {
            if let wv = w.contentView as? WKWebView {
                wv.stopLoading()
                wv.removeFromSuperview()
            }
            w.contentView = nil
            w.close()
        }
        windows.removeAll()
        videoContainers.removeAll()
        imageContainers.removeAll()
    }

    private func makeContainer(for content: WallpaperContent) -> NSView {
        switch content {
        case .image(let img, _):
            let v = ImageContainerView(frame: .zero)
            v.image = img
            v.fit = fitMode
            imageContainers.append(v)
            return v

        case .video:
            let v = VideoContainerView(frame: .zero)
            v.playerLayer.player = player
            v.playerLayer.videoGravity = fitMode == .fill ? .resizeAspectFill : .resizeAspect
            videoContainers.append(v)
            return v

        case .web(let html, _):
            let cfg = WKWebViewConfiguration()
            cfg.mediaTypesRequiringUserActionForPlayback = []
            let wv = WKWebView(frame: .zero, configuration: cfg)
            wv.autoresizingMask = [.width, .height]
            wv.allowsMagnification = false
            if #available(macOS 12.2, *) {
                wv.underPageBackgroundColor = .black
            }
            wv.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
            return wv
        }
    }

    private func applyFitMode() {
        let avGravity: AVLayerVideoGravity = fitMode == .fill ? .resizeAspectFill : .resizeAspect
        for v in videoContainers { v.playerLayer.videoGravity = avGravity }
        for v in imageContainers { v.fit = fitMode }
    }
}

// MARK: - 视频容器

final class VideoContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        updateLayerFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayerFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerFrame()
    }

    private func updateLayerFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - 图片容器（等比裁切 / 完整显示）

final class ImageContainerView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var fit: WallpaperFitMode = .fill { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let box = bounds.size
        let src = image.size
        let scale = fit == .fill
            ? max(box.width / src.width, box.height / src.height)
            : min(box.width / src.width, box.height / src.height)
        let w = src.width * scale
        let h = src.height * scale
        image.draw(in: CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h))
    }
}
