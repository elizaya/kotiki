import AppKit
import CryptoKit

/// Автообновление из релизов GitHub: раз в несколько часов смотрит последний релиз,
/// скачивает Kotiki.zip, проверяет его и подменяет приложение, когда за Маком никого нет.
final class Updater {
    static let shared = Updater()
    static let repo = "elizaya/kotiki"
    static let assetName = "Kotiki.zip"
    static let interval: TimeInterval = 6 * 3600

    enum Status { case unknown, checking, upToDate, failed }
    private enum Found { case none, staged(String, URL), manual(String, URL) }

    private(set) var status = Status.unknown
    /// скачанная и проверенная новая версия, ждёт установки
    private(set) var staged: (version: String, app: URL)?
    /// новая версия есть, но поставить её сами не можем — только открыть страницу релиза
    private(set) var manual: (version: String, page: URL)?
    private var nextCheck = Date.distantFuture
    private var timer: Timer?

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    private var bundleURL: URL { Bundle.main.bundleURL }
    private var feedOverride: String? { ProcessInfo.processInfo.environment["KOTIKI_UPDATE_URL"] }

    /// Нельзя подменить себя, если запущены из карантина (App Translocation) или из папки без прав на запись.
    private var canInstall: Bool {
        let fm = FileManager.default
        return !bundleURL.path.contains("/AppTranslocation/")
            && fm.isWritableFile(atPath: bundleURL.path)
            && fm.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path)
    }

    func start() {
        guard bundleURL.pathExtension == "app", timer == nil else { return }
        nextCheck = Date().addingTimeInterval(15)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard Prefs.autoUpdate else { return }
        if staged != nil {
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idle > 300 || ProcessInfo.processInfo.environment["KOTIKI_UPDATE_NOW"] != nil { install() }
        } else if Date() > nextCheck {
            check()
        }
    }

    func check() {
        guard status != .checking, staged == nil else { return }
        status = .checking
        nextCheck = Date().addingTimeInterval(Self.interval)
        Task.detached { [self] in
            let found = try? await fetch()
            await MainActor.run {
                switch found {
                case nil: status = .failed
                case .some(.none): status = .upToDate; manual = nil
                case .some(.staged(let v, let app)): status = .unknown; staged = (v, app); manual = nil
                case .some(.manual(let v, let page)): status = .unknown; manual = (v, page)
                }
            }
        }
    }

    private func fetch() async throws -> Found {
        let feed = URL(string: feedOverride ?? "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var req = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.isNewer(version, than: current) else { return .none }

        let page = (json["html_url"] as? String).flatMap(URL.init) ?? URL(string: "https://github.com/\(Self.repo)/releases/latest")!
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard canInstall,
              let asset = assets.first(where: { $0["name"] as? String == Self.assetName }),
              let link = (asset["browser_download_url"] as? String).flatMap(URL.init),
              feedOverride != nil || (link.scheme == "https" && link.host == "github.com")
        else { return .manual(version, page) }

        let fm = FileManager.default
        let (tmp, dresp) = try await URLSession.shared.download(from: link)
        defer { try? fm.removeItem(at: tmp) }
        guard (dresp as? HTTPURLResponse)?.statusCode == 200 else { throw CocoaError(.fileReadUnknown) }
        // GitHub отдаёт контрольную сумму файла — сверяем, если она есть
        if let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") {
            let sum = SHA256.hash(data: try Data(contentsOf: tmp)).map { String(format: "%02x", $0) }.joined()
            guard sum == digest.dropFirst(7).lowercased() else { throw CocoaError(.fileReadCorruptFile) }
        }

        // распаковываем на тот же том, где лежит приложение, чтобы подмена была одним переименованием
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundleURL, create: true)
        let app = dir.appendingPathComponent(bundleURL.lastPathComponent)
        do {
            try Self.run("/usr/bin/ditto", ["-x", "-k", tmp.path, dir.path])
            let unpacked = dir.appendingPathComponent("Kotiki.app")
            if unpacked != app { try fm.moveItem(at: unpacked, to: app) }
            // внутри должно быть это же приложение и действительно новее текущего,
            // иначе обновление будет ставиться по кругу
            guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  let inner = info["CFBundleShortVersionString"] as? String, Self.isNewer(inner, than: current)
            else { throw CocoaError(.fileReadCorruptFile) }
            try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
        return .staged(version, app)
    }

    /// Подменяет приложение скачанным и перезапускается.
    func install() {
        guard let s = staged else { return }
        staged = nil
        let stageDir = s.app.deletingLastPathComponent()
        do {
            _ = try FileManager.default.replaceItemAt(bundleURL, withItemAt: s.app)
        } catch {
            status = .failed
            try? FileManager.default.removeItem(at: stageDir)
            return
        }
        try? FileManager.default.removeItem(at: stageDir)
        // ждём, пока этот процесс завершится, и открываем новую версию
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; open \"$2\"", "sh",
                       String(ProcessInfo.processInfo.processIdentifier), bundleURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
    }
}
