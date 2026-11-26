import AppKit
import UniformTypeIdentifiers

/// 壁纸内容：静态图片 / 视频 / WE 网页壁纸
enum WallpaperContent {
    case image(NSImage, name: String)
    case video(URL, name: String)
    case web(URL, name: String) // index.html

    var name: String {
        switch self {
        case .image(_, let n), .video(_, let n), .web(_, let n): return n
        }
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }

    var isWeb: Bool {
        if case .web = self { return true }
        return false
    }
}

/// 从文件 / Wallpaper Engine 壁纸目录（含 project.json）加载壁纸
enum WallpaperLoader {

    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "tiff", "tif", "bmp"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]

    static func load(path: String) -> WallpaperContent? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        let url = URL(fileURLWithPath: path)
        if isDir.boolValue {
            return loadDirectory(url)
        }
        return loadFile(url)
    }

    // MARK: - 单文件

    static func loadFile(_ url: URL) -> WallpaperContent? {
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent
        if imageExts.contains(ext) {
            guard let img = NSImage(contentsOf: url) else { return nil }
            return .image(img, name: name)
        }
        if videoExts.contains(ext) {
            return .video(url, name: name)
        }
        return nil
    }

    // MARK: - 目录（WE 壁纸目录或普通文件夹）

    static func loadDirectory(_ dir: URL) -> WallpaperContent? {
        let fm = FileManager.default
        let pj = dir.appendingPathComponent("project.json")

        if fm.fileExists(atPath: pj.path),
           let data = try? Data(contentsOf: pj),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {

            let type = (obj["type"] as? String ?? "").lowercased()
            let title = (obj["title"] as? String) ?? dir.lastPathComponent
            // project.json 中显式指定的文件（不同 WE 版本字段可能不同）
            let fileKey = (obj["file"] as? String)
                ?? (obj["video"] as? String)
                ?? (obj["html"] as? String)
                ?? (obj["scene"] as? String)

            // 1) web 类型：找 index.html / 指定 html
            if type == "web" || type == "application" && fileKey?.hasSuffix(".html") == true {
                var html: URL?
                if let f = fileKey, f.lowercased().hasSuffix(".html") || f.lowercased().hasSuffix(".htm") {
                    let u = dir.appendingPathComponent(f)
                    if fm.fileExists(atPath: u.path) { html = u }
                }
                if html == nil { html = findFirst(dir, exts: ["html", "htm"]) }
                if let h = html { return .web(h, name: title) }
            }

            // 2) video 类型：指定文件或目录里第一个视频
            if type == "video" {
                if let f = fileKey, videoExts.contains(URL(fileURLWithPath: f).pathExtension.lowercased()) {
                    let u = dir.appendingPathComponent(f)
                    if fm.fileExists(atPath: u.path) { return .video(u, name: title) }
                }
                if let v = findFirst(dir, exts: Array(videoExts)) { return .video(v, name: title) }
            }

            // 3) 通用兜底：视频 → 网页 → 预览图
            if let v = findFirst(dir, exts: Array(videoExts)) { return .video(v, name: title) }
            if let h = findFirst(dir, exts: ["html", "htm"]) { return .web(h, name: title) }
            if let p = previewImage(obj, dir: dir), let img = NSImage(contentsOf: p) {
                return .image(img, name: title)
            }
            return nil
        }

        // 没有 project.json：普通文件夹，取第一个视频，否则第一张图
        let name = dir.lastPathComponent
        if let v = findFirst(dir, exts: Array(videoExts)) { return .video(v, name: name) }
        if let i = findFirst(dir, exts: Array(imageExts)), let img = NSImage(contentsOf: i) {
            return .image(img, name: name)
        }
        return nil
    }

    // MARK: - WE 预览图

    private static func previewImage(_ obj: [String: Any], dir: URL) -> URL? {
        // project.json 可能带 "preview" 字段
        if let p = obj["preview"] as? String {
            let u = dir.appendingPathComponent(p)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        // 兜底：preview.*（优先静态图，其次 gif）
        let prefs = ["jpg", "jpeg", "png", "webp", "gif"]
        for ext in prefs {
            if let u = findFirst(dir, exts: [ext], shallowOnly: true) { return u }
        }
        return nil
    }

    // MARK: - 查找工具

    private static func findFirst(_ dir: URL, exts: [String], shallowOnly: Bool = false) -> URL? {
        let set = Set(exts.map { $0.lowercased() })
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        var best: URL?
        var bestDepth = Int.max
        let baseDepth = dir.pathComponents.count
        for case let u as URL in en {
            guard set.contains(u.pathExtension.lowercased()) else { continue }
            let depth = u.pathComponents.count - baseDepth
            if depth > 1 && shallowOnly { continue }
            if depth < bestDepth {
                best = u
                bestDepth = depth
            }
            if depth <= 1 && bestDepth <= 1 && depth == 1 { /* keep scanning for equal-depth first */ }
        }
        return best
    }
}
