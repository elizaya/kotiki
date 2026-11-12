import AppKit
import SpriteKit

// MARK: настройки

enum Prefs {
    static let d = UserDefaults.standard
    private static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    private static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
    static var tom: Bool { get { bool("tom", true) } set { d.set(newValue, forKey: "tom") } }
    static var pirozhok: Bool { get { bool("pirozhok", true) } set { d.set(newValue, forKey: "pirozhok") } }
    /// 0 — пиксель-арт, 1 — иллюстрация
    static var style: Int { get { int("style", 1) } set { d.set(newValue, forKey: "style") } }
    /// 0 — выкл, 1 — лёгкий, 2 — обычный, 3 — метель
    static var snow: Int { get { int("snow", 2) } set { d.set(newValue, forKey: "snow") } }
    /// -2…2
    static var wind: Int { get { int("wind", 0) } set { d.set(newValue, forKey: "wind") } }
    /// 0 — редко, 1 — иногда, 2 — часто
    static var antics: Int { get { int("antics", 1) } set { d.set(newValue, forKey: "antics") } }
    static var trap: Bool { get { bool("trap", true) } set { d.set(newValue, forKey: "trap") } }
    static var play: Bool { get { bool("play", true) } set { d.set(newValue, forKey: "play") } }
    /// 0 — ⌥, 1 — ⇧, 2 — ⌘
    static var playKey: Int { get { int("playKey2", 0) } set { d.set(newValue, forKey: "playKey2") } }
    static var tomBreaks: Bool { get { bool("tomBreaks", true) } set { d.set(newValue, forKey: "tomBreaks") } }
    static var judge: Bool { get { bool("judge", true) } set { d.set(newValue, forKey: "judge") } }
    static var autoUpdate: Bool { get { bool("autoUpdate", true) } set { d.set(newValue, forKey: "autoUpdate") } }
    /// сколько своих котов можно завести
    static let maxSpecs = 4
    /// свои коты
    static var specs: [CatSpec] {
        get {
            if let a = d.array(forKey: "customCats") as? [[String: Any]] { return a.map { CatSpec(dict: $0) } }
            // в первой версии свой кот был один и лежал под другими ключами
            guard let one = d.dictionary(forKey: "customCat") else { return [] }
            var s = CatSpec(dict: one)
            s.id = "first"; s.on = bool("custom", false)
            return [s]
        }
        set { d.set(newValue.map { $0.dict }, forKey: "customCats") }
    }
}

// MARK: поверхности и сугробы

struct Surface {
    let id: Int
    var x0: CGFloat
    var x1: CGFloat
    var y: CGFloat
    var segs: [ClosedRange<CGFloat>]
    var catOK: Bool
    var cap: Float

    func seg(at x: CGFloat, tol: CGFloat = 0) -> ClosedRange<CGFloat>? {
        segs.first { x >= $0.lowerBound - tol && x <= $0.upperBound + tol }
    }
}

final class Pile {
    static let col: CGFloat = 3
    var h: [Float] = []
    let node = SKShapeNode()
    var dirty = true
    var key = ""

    init() {
        node.fillColor = .white
        node.strokeColor = NSColor(calibratedRed: 0.78, green: 0.85, blue: 0.93, alpha: 1)
        node.lineWidth = 1
        node.zPosition = 5
    }

    func resize(_ width: CGFloat) {
        let n = max(1, Int(ceil(width / Pile.col)))
        if n > h.count { h += [Float](repeating: 0, count: n - h.count); dirty = true }
        else if n < h.count { h.removeLast(h.count - n); dirty = true }
    }

    func height(at lx: CGFloat) -> CGFloat {
        let i = Int(lx / Pile.col)
        return i >= 0 && i < h.count ? CGFloat(h[i]) : 0
    }

    let ph1 = Float.random(in: 0...6.28), ph2 = Float.random(in: 0...6.28)

    /// Предел высоты в колонке: неровный, чтобы сугроб был с буграми, а не ровной полосой.
    func limit(_ i: Int, cap: Float) -> Float {
        let x = Float(i)
        let n = 0.5 + 0.3 * sin(x * 0.045 + ph1) + 0.2 * sin(x * 0.13 + ph2)
        return cap * (0.5 + 0.5 * n)
    }

    func add(at lx: CGFloat, _ amt: Float, cap: Float) {
        let i = Int(lx / Pile.col)
        guard i >= 0, i < h.count else { return }
        let k: [Float] = [0.3, 0.6, 1, 0.6, 0.3]
        for (o, w) in k.enumerated() {
            let j = i + o - 2
            guard j >= 0, j < h.count else { continue }
            let lim = limit(j, cap: cap)
            // чем ближе к пределу, тем медленнее растёт
            h[j] = min(lim, h[j] + amt * w * max(0.08, 1 - h[j] / lim))
        }
        dirty = true
    }

    func take(at lx: CGFloat, _ frac: Float) -> Float {
        let i = Int(lx / Pile.col)
        guard i >= 0, i < h.count, h[i] > 0.05 else { return 0 }
        let t = h[i] * frac
        h[i] -= t; dirty = true
        return t
    }

    func dent(at lx: CGFloat) {
        let i = Int(lx / Pile.col)
        for j in (i - 1)...(i + 1) where j >= 0 && j < h.count && h[j] > 0.3 { h[j] *= 0.45; dirty = true }
    }

    func relax() {
        guard h.count > 1 else { return }
        for i in 0..<(h.count - 1) {
            let d = h[i] - h[i + 1]
            if d > 1.5 { let m = (d - 1.5) / 2; h[i] -= m; h[i + 1] += m }
            else if d < -1.5 { let m = (-d - 1.5) / 2; h[i] += m; h[i + 1] -= m }
        }
    }

    func rebuild(segs: [ClosedRange<CGFloat>], x0: CGFloat, pixel: Bool) {
        relax()
        let c = Pile.col
        let p = CGMutablePath()
        for s in segs {
            let a = max(0, Int((s.lowerBound - x0) / c)), b = min(h.count - 1, Int((s.upperBound - x0) / c) - 1)
            guard b > a, h[a...b].contains(where: { $0 > 0.6 }) else { continue }
            p.move(to: CGPoint(x: CGFloat(a) * c, y: 0))
            for i in a...b {
                let edge = sqrt(CGFloat(min(i - a, b - i)) * c) * 3.4
                let avg = (h[max(a, i - 2)] + h[max(a, i - 1)] + h[i] + h[min(b, i + 1)] + h[min(b, i + 2)]) / 5
                var hh = min(CGFloat(pixel ? h[i] : avg), edge)
                if pixel {
                    hh = (hh / 3).rounded() * 3
                    p.addLine(to: CGPoint(x: CGFloat(i) * c, y: hh))
                    p.addLine(to: CGPoint(x: CGFloat(i + 1) * c, y: hh))
                } else {
                    p.addLine(to: CGPoint(x: (CGFloat(i) + 0.5) * c, y: hh))
                }
            }
            p.addLine(to: CGPoint(x: CGFloat(b + 1) * c, y: 0))
            p.closeSubpath()
        }
        node.isAntialiased = !pixel
        node.path = p
        dirty = false
    }
}

struct Flake {
    var x, y, vy, ph, size: CGFloat
    let node: SKSpriteNode
}

// MARK: кот

enum CatState { case stand, walk, sit, sitBack, sleep, seal, lounge, loaf, crouch, jump, fall, shake, stretch, drag, scratch, scratchWall }
enum SubAct { case none, swat, sneeze, yawn }

final class Cat {
    var look: CatLook
    let node = SKSpriteNode()
    var surf = -2
    var rel: CGFloat = 0
    var x: CGFloat = 0
    var y: CGFloat = 0
    var vy: CGFloat = 0
    var facing: CGFloat = 1
    var state = CatState.fall
    var t = 0.0
    var dur = 3.0
    var targetRel: CGFloat = 0
    var jFrom = CGPoint.zero
    var jSurf = -2
    var jRel: CGFloat = 0
    var jDur = 0.6
    var jH: CGFloat = 60
    var after: (CatState, Double)?
    var sub = SubAct.none
    var subT = 0.0
    var subCD = 3.0
    var subDone = false
    var snowCover: CGFloat = 0
    var headSnow: CGFloat = 0
    var napIdle = false
    var grabT = 0.0
    var grabCD = 0.0
    var huntCD = 4.0
    var shakeCD = 0.0
    var printT = 0.0
    var happy = 0.0
    var headTurn: CGFloat = 0
    var anim = Double.random(in: 0...10)
    var texT = 0.0
    var chase: Ball?
    var ballCD = 0.0
    var goal = Goal.none
    var catching = false
    var hoverT = 0.0
    /// только что разошёлся с другим котом — пока не трогаем
    var avoidT = 0.0
    /// чем кот был занят, когда из-под него ушла опора (Док выехал или спрятался)
    var resume: (CatState, Double)?
    /// сколько кот смотрит на курсор, прежде чем зевнуть
    var stare = 0.0
    /// через сколько секунд зевнёт вслед за другим котом
    var yawnIn = 0.0
    /// зевает «за компанию» — сам никого не заражает
    var yawnEcho = false
    /// чем заняться, когда досидит (например, зевнул — и спать)
    var sitThen: (CatState, Double)?
    /// только что проснулся
    var woke = false
    /// бежит, а не идёт
    var run = false
    /// тянется носом к другому коту
    var nuzzle = false
    /// встреча с другим котом, в которой он сейчас участвует
    var meet: Meet?

    init(_ look: CatLook) {
        self.look = look
        node.size = Art.canvas
        node.anchorPoint = CGPoint(x: 0.5, y: Art.ground / Art.canvas.height)
        node.zPosition = 10
    }

    var busy: Bool { [.jump, .fall, .crouch, .sleep, .seal, .stretch, .drag].contains(state) }
}

// MARK: сцена

final class OverlayScene: SKScene {
    weak var host: NSWindow?
    var surfaces: [Surface] = []
    var piles: [Int: Pile] = [:]
    var flakes: [Flake] = []
    var cats: [Cat] = []
    var last: TimeInterval = 0
    var clock = 0.0
    var surfT = 0.0
    var pileT = 0.0
    var known = Set<Int>()
    var primed = false
    var suitcaseCD = 15.0
    var trail: [(CGPoint, Double)] = []
    var mouse = CGPoint.zero
    var idle = 0.0
    let pid = Int(ProcessInfo.processInfo.processIdentifier)
    var dockCache: (DockInfo, Double) = (DockInfo(), -100)
    /// автоскрываемый Док сейчас выехал
    var dockUp = false
    var dockInT = 0.0
    var dockOutT = 0.0
    var forceDock = false
    /// прогон без экрана для проверки: коты не засыпают от бездействия
    var sim = false
    /// сколько секунд коты простояли друг на друге (для проверки)
    var overlapT = 0.0
    var scratches = 0
    /// края «земли»: экран минус Док, если он сбоку
    var groundL: CGFloat = 0
    var groundR: CGFloat = 0
    var judge: SKSpriteNode?
    var judgeT = 0.0
    var judgeLook = CatLook.tom
    var lastJudge = -1e9
    var judgeCheck = 5.0
    var balls: [Ball] = []
    var held: Ball?
    var snowmen: [Snowman] = []
    var ballTex: [String: (SKTexture, CGSize)] = [:]
    var prevMouse = CGPoint.zero
    var grabCat: Cat?
    var selfPlays = 0
    var bats = 0
    var knocks = 0
    var grabStart = CGPoint.zero
    var dragging = false
    var meet: Meet?
    var meetCD = Double.random(in: 40...90)
    var meets = 0
    var yawns = 0

    lazy var roundTex: SKTexture = {
        let n = 16
        let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(rgb(0xc9d7e6, 0.9)); c.fillEllipse(in: CGRect(x: 0, y: 0, width: n, height: n))
        c.setFillColor(rgb(0xffffff)); c.fillEllipse(in: CGRect(x: 1.5, y: 1.5, width: 13, height: 13))
        return SKTexture(cgImage: c.makeImage()!)
    }()
    lazy var squareTex: SKTexture = {
        let c = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(rgb(0xf4f8fc)); c.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let t = SKTexture(cgImage: c.makeImage()!); t.filteringMode = .nearest
        return t
    }()

    var style: ArtStyle { ArtStyle(rawValue: Prefs.style) ?? .illustration }
    var pixel: Bool { style == .pixel }
    var snowing: Bool { Prefs.snow > 0 }
    var W: CGFloat { size.width }
    var H: CGFloat { size.height }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        applyPrefs()
    }

    func applyCats() {
        var want: [CatLook] = (Prefs.tom ? [.tom] : []) + (Prefs.pirozhok ? [.pirozhok] : [])
        let own = Prefs.specs.filter { $0.on }.map { $0.look }
        want += own
        for c in cats where !want.contains(where: { $0.id == c.look.id }) { c.node.removeFromParent() }
        cats.removeAll { c in !want.contains(where: { $0.id == c.look.id }) }
        for l in want {
            // у своего кота внешность меняется на ходу
            if let c = cats.first(where: { $0.look.id == l.id }) { c.look = l; continue }
            let c = Cat(l)
            c.x = CGFloat.random(in: W * 0.2...W * 0.8); c.y = H + 40; c.state = .fall
            addChild(c.node); cats.append(c)
        }
        // у каждого кота свой слой: на одном слое спрайты мигают, когда перекрываются
        for c in cats {
            c.texT = 0
            let i = own.firstIndex { $0.id == c.look.id } ?? 0
            c.node.zPosition = ["tom": 10, "pirozhok": 10.5][c.look.id] ?? 10.1 + 0.05 * CGFloat(i)
        }
    }

    func applyPrefs() {
        applyCats()
        // снег
        let n = [0, 70, 150, 330][max(0, min(3, Prefs.snow))]
        while flakes.count > n { flakes.removeLast().node.removeFromParent() }
        while flakes.count < n {
            let node = SKSpriteNode(); node.zPosition = 20
            var f = Flake(x: 0, y: 0, vy: 0, ph: 0, size: 3, node: node)
            respawn(&f); f.y = CGFloat.random(in: 0...H)
            addChild(node); flakes.append(f)
        }
        for i in flakes.indices { styleFlake(&flakes[i]) }
        for p in piles.values { p.dirty = true }
        restylePlay()
    }

    func styleFlake(_ f: inout Flake) {
        if pixel {
            f.node.texture = squareTex
            let s: CGFloat = f.size > 4.2 ? 6 : 3
            f.node.size = CGSize(width: s, height: s)
        } else {
            f.node.texture = roundTex
            f.node.size = CGSize(width: f.size, height: f.size)
        }
    }

    func respawn(_ f: inout Flake) {
        f.x = CGFloat.random(in: -40...(W + 40)); f.y = H + CGFloat.random(in: 0...60)
        f.size = CGFloat.random(in: 2.2...5.2)
        f.vy = 28 + f.size * 11 + CGFloat.random(in: 0...12)
        f.ph = CGFloat.random(in: 0...6.28)
        styleFlake(&f)
    }

    func clearSnow() { for p in piles.values { for i in p.h.indices { p.h[i] = 0 }; p.dirty = true }; clearPlay() }

    // MARK: цикл

    override func update(_ now: TimeInterval) {
        let dt = last == 0 ? 1.0 / 30 : min(0.1, now - last)
        last = now; clock += dt
        mouse = NSEvent.mouseLocation
        idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if sim { idle = 0 }
        surfT -= dt; suitcaseCD -= dt
        trackDock(dt)
        if surfT <= 0 || NSEvent.pressedMouseButtons != 0 { refreshSurfaces(); surfT = 0.15 }
        stepSnow(CGFloat(dt))
        trackMouse()
        for c in cats {
            if hit(c, mouse) && held == nil && grabCat == nil && NSEvent.pressedMouseButtons == 0 {
                c.hoverT += dt
                if c.hoverT > 0.25, c.state == .walk, c.chase == nil { begin(c, .sit, 2.5) }
            } else { c.hoverT = 0 }
            step(c, dt)
        }
        stepMeet(dt)
        separate()
        for c in cats { paint(c, dt) }
        if let c = grabCat {
            if NSEvent.pressedMouseButtons & 1 == 0 {
                if dragging { begin(c, .fall) }
                else {
                    if c.state == .sleep { wake(c) } else { c.happy = 1.7 }
                    heart(at: CGPoint(x: c.x, y: c.y + 62 * c.look.size))
                }
                grabCat = nil; dragging = false
            } else if !dragging, hypot(mouse.x - grabStart.x, mouse.y - grabStart.y) > 6 {
                dragging = true
                if c.snowCover > 0.15 { puff(at: CGPoint(x: c.x, y: c.y + 24), 6) }
                c.snowCover = 0; c.grabT = 0
                begin(c, .drag)
            }
        }
        stepPlay(dt)
        stepJudge(dt)
        pileT -= dt
        if pileT <= 0 {
            pileT = 0.2
            for s in surfaces {
                guard let p = piles[s.id] else { continue }
                let key = s.segs.map { "\(Int($0.lowerBound - s.x0)):\(Int($0.upperBound - s.x0))" }.joined(separator: ",")
                if p.dirty || key != p.key { p.key = key; p.rebuild(segs: s.segs, x0: s.x0, pixel: pixel) }
            }
        }
        host?.ignoresMouseEvents = !(held != nil || grabCat != nil || playKeyDown || cats.contains { hit($0, mouse) })
    }

    func surface(_ id: Int) -> Surface? { surfaces.first { $0.id == id } }

    // MARK: окна

    struct DockInfo {
        var width: CGFloat = 600
        /// высота выехавшего Дока, когда он автоскрываемый
        var popH: CGFloat = 70
        var autohide = false
        var bottom = true
    }

    /// Точных размеров Дока без разрешений не узнать, поэтому ширину считаем по его настройкам
    /// и берём с запасом: лучше кот чуть не дойдёт до края Дока, чем окажется за ним.
    func dockInfo() -> DockInfo {
        if clock - dockCache.1 < 5 { return dockCache.0 }
        let dd = UserDefaults(suiteName: "com.apple.dock")
        var tile = CGFloat(dd?.double(forKey: "tilesize") ?? 0); if tile < 16 { tile = 48 }
        let tiles = dd?.array(forKey: "persistent-apps")
        var pinned = Set<String>()
        for t in tiles ?? [] {
            if let d = (t as? [String: Any])?["tile-data"] as? [String: Any], let b = d["bundle-identifier"] as? String { pinned.insert(b) }
        }
        let apps = tiles?.count ?? 16
        let others = dd?.array(forKey: "persistent-others")?.count ?? 1
        // запущенные программы, которых нет в Доке постоянно, тоже занимают в нём место
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != "com.apple.finder" && !pinned.contains($0.bundleIdentifier ?? "")
        }.count
        let recents = (dd?.object(forKey: "show-recents") as? Bool ?? true) ? max(3, running) : running
        let n = CGFloat(apps + others + 2 + recents)
        let w = (n + 1) * (tile * 1.1 + 3) + tile * 0.6 + 30
        let info = DockInfo(width: min(w, W - 20), popH: tile + 22, autohide: dd?.bool(forKey: "autohide") ?? false,
                            bottom: (dd?.string(forKey: "orientation") ?? "bottom") == "bottom")
        dockCache = (info, clock)
        return info
    }

    /// Автоскрываемый Док выезжает, когда курсор упирается в нижний край экрана,
    /// и прячется, когда курсор уходит выше него.
    func trackDock(_ dt: Double) {
        let info = dockInfo()
        var up = forceDock
        if !up, info.autohide, info.bottom, mouse.x >= 0, mouse.x <= W {
            let inside = mouse.y <= (dockUp || dockInT > 0 ? info.popH + 6 : 2)
            if inside { dockOutT = 0; dockInT += dt } else { dockOutT += dt; if dockOutT > 0.25 { dockInT = 0 } }
            up = inside ? (dockUp || dockInT > 0.45) : (dockUp && dockOutT <= 0.25)
        } else if !up { dockInT = 0 }
        if up != dockUp { dockUp = up; surfT = 0 }
    }

    func refreshSurfaces() {
        guard let screen = NSScreen.screens.first else { return }
        let menuBottom = screen.frame.maxY - screen.visibleFrame.maxY
        let dockH = screen.visibleFrame.minY - screen.frame.minY
        var rects: [(Int, CGRect)] = []
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
            for w in list {
                guard (w[kCGWindowLayer as String] as? Int) == 0,
                      (w[kCGWindowOwnerPID as String] as? Int) != pid,
                      (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                      let b = w[kCGWindowBounds as String] as? NSDictionary,
                      let r = CGRect(dictionaryRepresentation: b), r.width > 100, r.height > 50,
                      let id = w[kCGWindowNumber as String] as? Int else { continue }
                rects.append((id, r))
            }
        }
        var out: [Surface] = []
        for (i, (id, r)) in rects.enumerated() {
            // нижний край окна: кот стоит внутри окна, на его «полу»
            let by = H - r.maxY
            if by > max(24, dockH + 24), r.height > 110 {
                var segs = [max(0, r.minX + 6)...max(0, min(W, r.maxX - 6))]
                for j in 0..<i {
                    let f = rects[j].1
                    if f.minY <= r.maxY - 2 && f.maxY >= r.maxY - 40 { segs = cut(segs, f.minX - 2, f.maxX + 2) }
                }
                segs = segs.filter { $0.upperBound - $0.lowerBound >= 24 }
                if !segs.isEmpty {
                    out.append(Surface(id: id + 1_000_000_000, x0: r.minX, x1: r.maxX, y: by, segs: segs, catOK: true, cap: 10))
                }
            }
            let y = H - r.minY
            guard r.minY > menuBottom + 3, y > dockH + 30 else { continue }
            var segs = [max(0, r.minX)...max(0, min(W, r.maxX))]
            for j in 0..<i {
                let f = rects[j].1
                if f.minY <= r.minY - 1 && f.maxY >= r.minY - 1 { segs = cut(segs, f.minX - 2, f.maxX + 2) }
            }
            segs = segs.filter { $0.upperBound - $0.lowerBound >= 24 }
            guard !segs.isEmpty else { continue }
            out.append(Surface(id: id, x0: r.minX, x1: r.maxX, y: y, segs: segs,
                               catOK: y + 75 < H - menuBottom, cap: 16))
        }
        // Док и «земля»
        // Док бывает постоянный (тогда система сама отдаёт его высоту), автоскрываемый (есть, пока выехал) и сбоку
        groundL = max(0, screen.visibleFrame.minX - screen.frame.minX)
        groundR = max(groundL + 1, min(W, screen.visibleFrame.maxX - screen.frame.minX))
        let info = dockInfo()
        let dh = dockH > 20 ? dockH : (dockUp ? info.popH : 0)
        if dh > 20 {
            let a = max(groundL, (W - info.width) / 2), b = min(groundR, (W + info.width) / 2)
            out.append(Surface(id: -1, x0: a, x1: b, y: dh, segs: [a...b], catOK: true, cap: 20))
            let sides = [groundL...a, b...groundR].filter { $0.upperBound - $0.lowerBound >= 24 }
            out.append(Surface(id: -2, x0: 0, x1: W, y: 0, segs: sides, catOK: !sides.isEmpty, cap: 30))
        } else {
            out.append(Surface(id: -2, x0: 0, x1: W, y: 0, segs: [groundL...groundR], catOK: true, cap: 30))
        }
        surfaces = out
        // сугробы
        let ids = Set(out.map { $0.id })
        for (id, p) in piles where !ids.contains(id) { p.node.removeFromParent(); piles[id] = nil }
        for s in out {
            let p: Pile
            if let e = piles[s.id] { p = e } else { p = Pile(); piles[s.id] = p; addChild(p.node) }
            p.resize(s.x1 - s.x0)
            p.node.position = CGPoint(x: s.x0, y: s.y)
        }
        // новое окно — «это теперь моё»
        let winIDs = Set(rects.map { $0.0 })
        if primed, suitcaseCD <= 0 {
            for id in winIDs.subtracting(known) {
                guard let s = surface(id), s.catOK, let seg = s.segs.max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound }),
                      seg.upperBound - seg.lowerBound > 90, Double.random(in: 0...1) < 0.45 + 0.2 * Double(Prefs.antics) else { continue }
                claim(s, seg)
                break
            }
        }
        known = winIDs
        if clock > 3 { primed = true }
    }

    func cut(_ segs: [ClosedRange<CGFloat>], _ a: CGFloat, _ b: CGFloat) -> [ClosedRange<CGFloat>] {
        var out: [ClosedRange<CGFloat>] = []
        for s in segs {
            if b <= s.lowerBound || a >= s.upperBound { out.append(s); continue }
            if a > s.lowerBound { out.append(s.lowerBound...a) }
            if b < s.upperBound { out.append(b...s.upperBound) }
        }
        return out
    }

    @discardableResult
    func claim(_ s: Surface, _ seg: ClosedRange<CGFloat>) -> Bool {
        let free = cats.filter { !$0.busy }
        guard let c = free.min(by: { abs($0.x - s.x0) < abs($1.x - s.x0) }) else { return false }
        let tx = (seg.lowerBound + seg.upperBound) / 2 + CGFloat.random(in: -20...20)
        jump(c, to: s, x: tx, after: (.loaf, Double.random(in: 14...22)))
        suitcaseCD = 40
        return true
    }

    // MARK: снег

    func stepSnow(_ dt: CGFloat) {
        let wind = CGFloat(Prefs.wind) * 38
        let px = pixel
        for i in flakes.indices {
            var f = flakes[i]
            let prev = f.y
            f.ph += dt * 1.5
            f.y -= f.vy * dt
            f.x += (wind + sin(f.ph) * 12) * dt
            if f.x < -50 { f.x += W + 100 } else if f.x > W + 50 { f.x -= W + 100 }
            var landed = false
            for s in surfaces where prev >= s.y && f.y < s.y + CGFloat(s.cap) {
                guard s.seg(at: f.x) != nil, let p = piles[s.id] else { continue }
                let top = s.y + p.height(at: f.x - s.x0)
                if f.y <= top {
                    p.add(at: f.x - s.x0, Float(f.size) * 1.0, cap: s.cap)
                    landed = true
                    break
                }
            }
            if landed || f.y < -8 { respawn(&f) }
            f.node.position = px ? CGPoint(x: (f.x / 3).rounded() * 3, y: (f.y / 3).rounded() * 3) : CGPoint(x: f.x, y: f.y)
            flakes[i] = f
        }
    }

    func puff(at p: CGPoint, _ n: Int) {
        for _ in 0..<n {
            let node = SKSpriteNode(texture: pixel ? squareTex : roundTex)
            let s: CGFloat = pixel ? 3 : CGFloat.random(in: 2.5...5)
            node.size = CGSize(width: s, height: s); node.position = p; node.zPosition = 21
            addChild(node)
            let dx = CGFloat.random(in: -45...45), up = CGFloat.random(in: 10...40)
            let a = SKAction.sequence([
                .group([.moveBy(x: dx * 0.5, y: up, duration: 0.25), .fadeAlpha(to: 0.9, duration: 0.25)]),
                .group([.moveBy(x: dx * 0.5, y: -up - 30, duration: 0.55), .fadeOut(withDuration: 0.55)]),
                .removeFromParent()])
            node.run(a)
        }
    }

    func heart(at p: CGPoint) {
        let l = SKLabelNode(text: "♥")
        l.fontSize = 18; l.fontColor = NSColor(calibratedRed: 1, green: 0.42, blue: 0.55, alpha: 1)
        l.position = p; l.zPosition = 22
        addChild(l)
        l.run(.sequence([.group([.moveBy(x: 0, y: 42, duration: 1.2), .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.6)])]), .removeFromParent()]))
    }

    // MARK: мышь

    func hit(_ c: Cat, _ p: CGPoint) -> Bool {
        let s = c.look.size
        return abs(p.x - c.x) < 36 * s && p.y > c.y - 4 && p.y < c.y + 64 * s
    }

    func trackMouse() {
        trail.append((mouse, clock))
        trail.removeAll { clock - $0.1 > 0.7 }
        guard trail.count > 6, let first = trail.first else { return }
        var path: CGFloat = 0
        for i in 1..<trail.count { path += hypot(trail[i].0.x - trail[i - 1].0.x, trail[i].0.y - trail[i - 1].0.y) }
        let net = hypot(mouse.x - first.0.x, mouse.y - first.0.y)
        guard path > 550, net < 260 else { return }
        for c in cats where c.huntCD <= 0 && !c.busy && c.meet == nil && c.look.can("hunt") && abs(mouse.x - c.x) < 380 && abs(mouse.y - c.y) < 320 {
            startHunt(c)
        }
    }

    func startHunt(_ c: Cat) {
        c.facing = mouse.x >= c.x ? 1 : -1
        c.huntCD = 9
        begin(c, .crouch, 0.9)
    }

    override func rightMouseDown(with event: NSEvent) { mouseDown(with: event) }

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        if tryGrab(p) { return }
        if let c = cats.first(where: { hit($0, p) }) { grabCat = c; grabStart = p; dragging = false }
    }

    // MARK: поведение

    func begin(_ c: Cat, _ s: CatState, _ dur: Double = 3) {
        c.state = s; c.t = 0; c.dur = dur; c.sub = .none; c.subCD = Double.random(in: 2...5)
        if s == .fall { c.vy = 0 }
        if s == .walk || s == .jump { c.headSnow = 0 }
        c.chase = nil
        if s != .jump { c.catching = false }
        if s != .walk && s != .sit { c.goal = .none }
        if s != .fall && s != .jump { c.resume = nil }
        c.sitThen = nil; c.woke = false; c.run = false; c.nuzzle = false; c.yawnIn = 0
        c.texT = 0
    }

    func wake(_ c: Cat) {
        if c.snowCover > 0.15 { puff(at: CGPoint(x: c.x, y: c.y + 24 * c.look.size), Int(c.snowCover * 14) + 3) }
        c.snowCover = 0
        begin(c, .stretch, 1.3)
        c.woke = true
    }

    /// Засыпает: сначала садится и зевает, если умеет.
    func dozeOff(_ c: Cat, _ dur: Double) {
        c.napIdle = false
        guard c.look.can("yawn") else { begin(c, .sleep, dur); return }
        begin(c, .sit, 2.7); startSub(c, .yawn)
        c.stare = 0.5; c.sitThen = (.sleep, dur)
    }

    func jump(_ c: Cat, to s: Surface, x: CGFloat, after: (CatState, Double)?, height: CGFloat? = nil) {
        // не приземляемся на другого кота: сдвигаем точку в сторону
        var x = x
        for o in cats where o !== c {
            guard let p = spot(o), abs(p.y - s.y) < 50, abs(p.x - x) < gap(c, o), let seg = s.seg(at: x, tol: 6) else { continue }
            let g = gap(c, o) + 8, d: CGFloat = x >= p.x ? 1 : -1
            for dd in [d, -d] {
                let nx = p.x + dd * g
                if nx >= seg.lowerBound + 12 && nx <= seg.upperBound - 12 { x = nx; break }
            }
        }
        c.jFrom = CGPoint(x: c.x, y: c.y)
        c.jSurf = s.id; c.jRel = x - s.x0
        let dist = hypot(x - c.x, s.y - c.y)
        c.jDur = Double(0.45 + dist / 1100)
        c.jH = height ?? (45 + dist * 0.12 + max(0, s.y - c.y) * 0.15)
        c.after = after
        if abs(x - c.x) > 2 { c.facing = x > c.x ? 1 : -1 }
        begin(c, .jump)
    }

    func randomJump(_ c: Cat) -> Bool {
        var spots: [(Surface, ClosedRange<CGFloat>)] = []
        for s in surfaces where s.catOK && s.id != c.surf {
            for g in s.segs where g.upperBound - g.lowerBound >= 80 { spots.append((s, g)) }
        }
        guard let (s, g) = spots.randomElement() else { return false }
        jump(c, to: s, x: CGFloat.random(in: (g.lowerBound + 28)...(g.upperBound - 28)), after: nil)
        return true
    }

    func next(_ c: Cat) {
        guard let s = surface(c.surf), let seg = s.seg(at: s.x0 + c.rel, tol: 6) else { begin(c, .fall); return }
        c.goal = .none
        if c.meet != nil { meetNext(c); return }
        if playNext(c, s) { return }
        let a = [0.5, 1.0, 1.9][max(0, min(2, Prefs.antics))]
        let wide = seg.upperBound - seg.lowerBound > 70
        let wall = wallSpot(c, s, seg)
        // характер: активный больше ходит и прыгает, ленивый больше лежит
        let L = c.look, act = 0.5 + L.activity, lazy = 1.5 - L.activity
        func can(_ k: String) -> Double { L.can(k) ? 1 : 0 }
        var opts: [(CatState, Double)] = [
            (.walk, wide ? 5 * act : 0), (.sit, 2.5), (.jump, (wide ? 1.4 : 4) * act),
            (.sitBack, (snowing ? 1.3 : 0.5) * a * can("window")),
            (.seal, 1.0 * a * can("seal")), (.lounge, s.id == -2 ? 0 : 0.9 * a * lazy * can("lounge")),
            (.loaf, 0.6 * a * lazy * can("loaf")), (.sleep, 0.35 * lazy), (.stand, 0.6),
            (.scratch, 0.8 * a * can("scratch")), (.scratchWall, wall != nil ? 1.0 * a * can("scratch") : 0)]
        opts.removeAll { $0.0 == c.state || $0.1 <= 0 }
        var r = Double.random(in: 0..<opts.reduce(0) { $0 + $1.1 })
        var pick = CatState.sit
        for o in opts { r -= o.1; if r < 0 { pick = o.0; break } }
        switch pick {
        case .walk:
            // гуляем только по своей стороне от другого кота
            var lo = seg.lowerBound + 24, hi = seg.upperBound - 24
            for o in cats where o !== c {
                guard let p = spot(o), abs(p.y - c.y) < 50 else { continue }
                if p.x < c.x { lo = max(lo, p.x + gap(c, o) + 8) } else { hi = min(hi, p.x - gap(c, o) - 8) }
            }
            let tx = CGFloat.random(in: lo...max(lo, hi))
            if abs(tx - c.x) < 30 { begin(c, .sit, Double.random(in: 2...5)); return }
            c.targetRel = tx - s.x0
            begin(c, .walk)
        case .jump: if !randomJump(c) { begin(c, .sit, Double.random(in: 2...5)) }
        case .sit: begin(c, .sit, Double.random(in: 3...8))
        case .sitBack: begin(c, .sitBack, Double.random(in: 6...12))
        case .seal: begin(c, .seal, Double.random(in: 7...13))
        case .lounge: begin(c, .lounge, Double.random(in: 9...18))
        case .loaf: begin(c, .loaf, Double.random(in: 8...16))
        case .sleep: dozeOff(c, Double.random(in: 20...40))
        case .scratch: begin(c, .scratch, Double.random(in: 3...5))
        case .scratchWall: if let w = wall { goWall(c, s, w) } else { begin(c, .scratch, Double.random(in: 3...5)) }
        default: begin(c, .stand, Double.random(in: 0.8...2))
        }
    }

    func step(_ c: Cat, _ dt: Double) {
        let d = CGFloat(dt)
        c.t += dt; c.anim += dt
        c.grabCD -= dt; c.huntCD -= dt; c.shakeCD -= dt; c.happy -= dt; c.avoidT -= dt
        if c.state != .jump && c.state != .fall && c.state != .drag {
            if let s = surface(c.surf), s.seg(at: s.x0 + c.rel, tol: 6) != nil { c.x = s.x0 + c.rel; c.y = s.y }
            else {
                // опора ушла (например, выехал или спрятался Док) — потом вернёмся к тому же занятию
                let was = (c.state, max(1.5, c.dur - c.t))
                begin(c, .fall)
                if [.stand, .sit, .sitBack, .sleep, .seal, .lounge, .loaf].contains(was.0) { c.resume = was }
            }
        }
        if idle > 300, c.avoidT <= 0, [.walk, .stand, .sit, .sitBack, .lounge, .loaf, .scratch, .scratchWall].contains(c.state) {
            if c.meet != nil { endMeet() }
            c.napIdle = true; begin(c, .sleep, 1e9)
        }
        switch c.state {
        case .fall:
            c.vy += 1500 * d
            let ny = c.y - c.vy * d
            let below = surfaces.filter { $0.y <= c.y + 0.5 && $0.seg(at: c.x) != nil }.max { $0.y < $1.y }
            let land = below ?? surfaces.filter { $0.seg(at: c.x) != nil }.min { $0.y < $1.y }
            let fy = below?.y ?? land?.y ?? 0
            if below == nil, let l = land, l.y > c.y + 1 {
                // под котом выросла опора (выехал Док) — запрыгиваем на неё
                jump(c, to: l, x: c.x, after: c.resume, height: 24)
                c.jDur = 0.32
            } else if ny <= fy || below == nil {
                c.y = fy
                if let l = land { c.surf = l.id; c.rel = c.x - l.x0 } else { c.surf = -2; c.rel = min(max(c.x, 30), W - 30) }
                if let r = c.resume { begin(c, r.0 == .lounge && c.surf == -2 ? .loaf : r.0, r.1) }
                else { begin(c, .sit, Double.random(in: 1.5...3)) }
            } else { c.y = ny }
        case .walk:
            guard let s = surface(c.surf) else { break }
            if let b = c.chase {
                if b.mode == .rolling || b.mode == .resting, b.surf == c.surf, !b.dead { c.targetRel = b.rel }
                else { c.chase = nil; next(c); break }
            }
            let dir: CGFloat = c.targetRel > c.rel ? 1 : -1
            c.facing = dir
            if blocked(c, dir: dir) {
                // впереди другой кот — не проходим сквозь него
                if let m = c.meet {
                    // в догонялках это значит «догнал»
                    // (а убегающий, упёршись в третьего кота, просто останавливается)
                    let o = c === m.a ? m.b : m.a
                    if m.kind == .chase, m.phase == 2, c === m.runner || abs(o.x - c.x) < gap(c, o) + 40 { meetNext(c); break }
                    endMeet()
                }
                c.goal = .none; c.ballCD = max(c.ballCD, 3)
                begin(c, .sit, Double.random(in: 1.5...3)); break
            }
            var toWall = false
            if case .wall = c.goal { toWall = true }
            c.rel += dir * c.look.speed * (c.chase != nil || c.run ? 2.4 : 1) * d
            c.printT -= dt
            if let p = piles[c.surf] {
                if c.printT <= 0 { c.printT = 0.22; p.dent(at: c.rel + dir * 8) }
                if c.shakeCD <= 0, c.chase == nil, !c.run, p.height(at: c.rel + dir * 14) > 4.5, Double.random(in: 0...1) < dt * 0.6 {
                    c.shakeCD = 12; begin(c, .shake, 1.2); break
                }
            }
            if abs(c.targetRel - c.rel) < (c.chase != nil ? 24 : 3) { arrive(c) }
            else if !toWall, s.seg(at: s.x0 + c.rel + dir * 14, tol: 0) == nil { next(c) }
        case .stand, .lounge, .loaf:
            if c.t > c.dur { next(c) }
        case .sit:
            if snowing { c.headSnow = min(1, c.headSnow + d / 30) }
            if c.sub == .none {
                if c.yawnIn > 0 {
                    // другой кот зевнул — зеваем следом
                    c.yawnIn -= dt
                    if c.yawnIn <= 0 { startSub(c, .yawn); c.stare = 0.2; c.yawnEcho = true }
                    break
                }
                c.subCD -= dt * [0.6, 1.0, 1.6][max(0, min(2, Prefs.antics))]
                if c.subCD <= 0 {
                    var subs: [SubAct] = snowing ? [.swat, .sneeze] : []
                    if c.look.can("yawn"), Double.random(in: 0...1) < 0.35 { subs.append(.yawn) }
                    if let s = subs.randomElement() { startSub(c, s) } else { c.subCD = Double.random(in: 4...9) }
                } else if c.t > c.dur {
                    if let n = c.sitThen { begin(c, n.0, n.1) } else { next(c) }
                }
            } else {
                c.subT += dt
                if c.sub == .swat, !c.subDone, c.subT > 0.4 {
                    c.subDone = true
                    playSwat(c)
                    let paw = CGPoint(x: c.x + 20 * c.facing, y: c.y + 46 * c.look.size)
                    if let i = flakes.indices.min(by: { hypot(flakes[$0].x - paw.x, flakes[$0].y - paw.y) < hypot(flakes[$1].x - paw.x, flakes[$1].y - paw.y) }),
                       hypot(flakes[i].x - paw.x, flakes[i].y - paw.y) < 70 { respawn(&flakes[i]) }
                }
                if c.sub == .yawn, !c.subDone, c.subT > c.stare + 0.8 {
                    c.subDone = true; yawns += 1
                    // зевота заразна: кто сидит рядом, зевнёт следом
                    if !c.yawnEcho {
                        for o in cats where o !== c && o.state == .sit && o.sub == .none && o.yawnIn <= 0 && o.look.can("yawn")
                            && hypot(o.x - c.x, o.y - c.y) < 600 {
                            o.yawnIn = Double.random(in: 1.2...2.4); o.dur = max(o.dur, o.t + 5)
                        }
                    }
                }
                let len = c.sub == .swat ? 0.9 : (c.sub == .yawn ? c.stare + Self.yawnLen : 0.7)
                if c.subT > len { c.sub = .none; c.subCD = Double.random(in: 4...9); c.yawnEcho = false }
            }
        case .sitBack:
            if snowing { c.headSnow = min(1, c.headSnow + d / 30) }
            let near: CGFloat = hypot(mouse.x - c.x, mouse.y - (c.y + 30)) < 150 ? 1 : 0
            c.headTurn += (near - c.headTurn) * min(1, d * 6)
            if c.t > c.dur && near == 0 { next(c) }
        case .sleep:
            if snowing { c.snowCover = min(1, c.snowCover + d / 45) }
            if c.napIdle ? (idle < 1 && c.t > 1.5) : (c.t > c.dur) { wake(c) }
        case .seal:
            let belly = CGPoint(x: c.x - 2 * c.facing * c.look.size, y: c.y + 19 * c.look.size)
            let free = NSEvent.pressedMouseButtons == 0
            if c.grabT > 0 {
                c.grabT -= dt
                if Prefs.trap && free {
                    let j = CGPoint(x: belly.x + CGFloat(sin(clock * 30)) * 2, y: belly.y + 4 + CGFloat(cos(clock * 23)) * 1.5)
                    CGWarpMouseCursorPosition(CGPoint(x: j.x, y: H - j.y))
                    CGAssociateMouseAndMouseCursorPosition(1)
                }
                if c.grabT <= 0 { c.grabCD = 14; c.happy = 1.5 }
            } else if c.grabCD <= 0, free, hypot(mouse.x - belly.x, mouse.y - belly.y) < 20 * c.look.size {
                c.grabT = 1.4
            } else if c.t > c.dur { next(c) }
        case .crouch:
            if c.t > c.dur {
                if c.meet != nil { next(c); break }
                guard let s = surface(c.surf), let seg = s.seg(at: c.x, tol: 6) else { begin(c, .fall); break }
                var tx = min(max(mouse.x, c.x - 240), c.x + 240)
                tx = min(max(tx, seg.lowerBound + 20), max(seg.lowerBound + 20, seg.upperBound - 20))
                jump(c, to: s, x: tx, after: (.sit, 2), height: 38)
                c.jDur = 0.45
            }
        case .jump:
            guard let s = surface(c.jSurf) else { begin(c, .fall); break }
            let u = CGFloat(min(1, c.t / c.jDur))
            let to = CGPoint(x: s.x0 + c.jRel, y: s.y)
            c.x = c.jFrom.x + (to.x - c.jFrom.x) * u
            c.y = c.jFrom.y + (to.y - c.jFrom.y) * u + 4 * c.jH * u * (1 - u)
            if u >= 1 {
                c.surf = s.id; c.rel = c.jRel
                if s.seg(at: to.x, tol: 6) == nil { begin(c, .fall); break }
                piles[s.id]?.dent(at: c.rel)
                if let a = c.after { c.after = nil; begin(c, a.0, a.1) }
                else if c.meet != nil { begin(c, .stand, 0.15) }
                else { begin(c, .sit, Double.random(in: 2...4)) }
                if c.state == .sit { c.happy = 0 }
            }
        case .shake:
            if c.t > c.dur { if abs(c.targetRel - c.rel) > 6 { begin(c, .walk) } else { next(c) } }
        case .stretch:
            if c.t > c.dur {
                // спросонья зевает
                if c.woke, c.meet == nil, c.look.can("yawn"), Double.random(in: 0...1) < 0.6 {
                    begin(c, .sit, 3); startSub(c, .yawn); c.stare = 0.4
                } else { next(c) }
            }
        case .scratch:
            // дерёт пол: по снегу — летит снег, по голому — остаются царапины
            c.printT -= dt
            if c.printT <= 0 {
                c.printT = 0.3
                let reach = 30 * c.look.size * c.facing
                if let p = piles[c.surf], p.height(at: c.rel + reach) > 1.5 {
                    p.dent(at: c.rel + reach); puff(at: CGPoint(x: c.x + reach, y: c.y + 4), 1)
                } else {
                    clawMarks(at: CGPoint(x: c.x + reach + CGFloat.random(in: -5...5), y: c.y), wall: false, inward: 1)
                }
            }
            if c.t > c.dur { next(c) }
        case .scratchWall:
            c.printT -= dt
            if c.printT <= 0 {
                c.printT = 0.35
                let s = c.look.size
                clawMarks(at: CGPoint(x: c.x + c.facing * Art.wallReach * s, y: c.y + CGFloat.random(in: 46...62) * s), wall: true, inward: -c.facing)
            }
            if c.t > c.dur { next(c) }
        case .drag:
            c.x = min(max(mouse.x, 20), W - 20)
            c.y = mouse.y - 42 * c.look.size
        }
    }

    /// сколько длится сам зевок
    static let yawnLen = 1.9

    func startSub(_ c: Cat, _ s: SubAct) {
        c.sub = s; c.subT = 0; c.subDone = false
        if s == .yawn { c.stare = Double.random(in: 2.5...4.5); c.yawnEcho = false }
        if s == .sneeze { puff(at: CGPoint(x: c.x, y: c.y + 40 * c.look.size), 4); c.headSnow = 0 }
    }

    // MARK: коты не пересекаются

    /// Сколько места по горизонтали нужно двум котам, чтобы не налезать друг на друга.
    func gap(_ a: Cat, _ b: Cat) -> CGFloat {
        // на встрече коты могут сидеть и спать вплотную
        if let m = a.meet, m === b.meet, let t = m.tight { return t }
        return 33 * (a.look.size + b.look.size)
    }

    /// Где кот стоит или куда приземлится; nil — он в воздухе или в руке.
    func spot(_ o: Cat) -> CGPoint? {
        switch o.state {
        case .drag, .fall: return nil
        case .jump:
            guard let s = surface(o.jSurf) else { return nil }
            return CGPoint(x: s.x0 + o.jRel, y: s.y)
        default: return CGPoint(x: o.x, y: o.y)
        }
    }

    /// Вплотную впереди стоит другой кот.
    func blocked(_ c: Cat, dir: CGFloat) -> Bool {
        for o in cats where o !== c {
            guard let p = spot(o), abs(p.y - c.y) < 50 else { continue }
            let dx = (p.x - c.x) * dir
            if dx > 0 && dx < gap(c, o) + 4 { return true }
        }
        return false
    }

    /// По пути до точки x нет другого кота.
    func pathFree(_ c: Cat, to x: CGFloat) -> Bool {
        let dir: CGFloat = x >= c.x ? 1 : -1
        for o in cats where o !== c {
            guard let p = spot(o), abs(p.y - c.y) < 50 else { continue }
            let dx = (p.x - c.x) * dir
            if dx > 0 && dx < abs(x - c.x) + gap(c, o) { return false }
        }
        return true
    }

    /// Если коты всё-таки оказались друг на друге (упали, их уронили), один отходит в свою сторону.
    func separate() {
        guard cats.count > 1 else { return }
        for i in 0..<(cats.count - 1) {
            for j in (i + 1)..<cats.count {
                let a = cats[i], b = cats[j]
                guard a.avoidT <= 0, b.avoidT <= 0, a.state != .jump, b.state != .jump,
                      let pa = spot(a), let pb = spot(b), abs(pa.y - pb.y) < 50 else { continue }
                let g = gap(a, b)
                guard abs(pa.x - pb.x) < g - 8 else { continue }
                overlapT += 1.0 / 30
                // первым уходит тот, кто на ногах; спящего будим в последнюю очередь
                func rank(_ c: Cat) -> Int { [.walk, .stand, .sit, .shake].contains(c.state) ? 0 : (c.state == .sleep ? 2 : 1) }
                let order = rank(a) <= rank(b) ? [a, b] : [b, a]
                var done = false
                for m in order where !done {
                    let o = m === a ? b : a
                    guard let s = surface(m.surf), let seg = s.seg(at: m.x, tol: 6) else { continue }
                    let dir: CGFloat = m.x == o.x ? (m === a ? -1 : 1) : (m.x > o.x ? 1 : -1)
                    let tx = o.x + dir * (g + 12)
                    guard tx >= seg.lowerBound + 16, tx <= seg.upperBound - 16 else { continue }
                    if m.state == .sleep { m.snowCover = 0 }
                    m.targetRel = tx - s.x0
                    begin(m, .walk)
                    done = true
                }
                if !done { for m in order where !done { done = randomJump(m) } }
                if done { a.avoidT = 2.5; b.avoidT = 2.5 }
            }
        }
    }

    // MARK: когти

    /// Стена рядом с котом: край экрана для «земли» и боковой край окна для кота внутри окна.
    /// Возвращает, где коту встать и в какую сторону смотреть.
    func wallSpot(_ c: Cat, _ s: Surface, _ seg: ClosedRange<CGFloat>, maxDist: CGFloat = 520) -> (CGFloat, CGFloat)? {
        guard seg.upperBound - seg.lowerBound > 70 else { return nil }
        var walls: [(CGFloat, CGFloat)] = []
        if s.id == -2 {
            if seg.lowerBound <= groundL + 1 { walls.append((groundL, -1)) }
            if seg.upperBound >= groundR - 1 { walls.append((groundR, 1)) }
        } else if s.id >= 1_000_000_000 {
            if abs(seg.lowerBound - max(0, s.x0 + 6)) < 1 { walls.append((max(0, s.x0), -1)) }
            if abs(seg.upperBound - min(W, s.x1 - 6)) < 1 { walls.append((min(W, s.x1), 1)) }
        }
        let reach = Art.wallReach * c.look.size
        return walls.map { ($0.0 - $0.1 * reach, $0.1) }
            .filter { abs($0.0 - c.x) < maxDist && pathFree(c, to: $0.0) }
            .min { abs($0.0 - c.x) < abs($1.0 - c.x) }
    }

    func goWall(_ c: Cat, _ s: Surface, _ w: (CGFloat, CGFloat), dur: Double? = nil) {
        let d = dur ?? Double.random(in: 3.5...6)
        scratches += 1
        if abs(w.0 - c.x) < 3 { c.facing = w.1; begin(c, .scratchWall, d); return }
        c.targetRel = w.0 - s.x0
        begin(c, .walk)
        c.goal = .wall(w.1, d)
    }

    /// Следы когтей: три короткие бороздки вдоль пола или стены, которые быстро тают.
    func clawMarks(at p: CGPoint, wall: Bool, inward: CGFloat) {
        let path = CGMutablePath()
        for i in 0..<3 {
            let o = 1.5 + CGFloat(i) * 2.6, len = CGFloat.random(in: 7...11)
            if wall {
                path.move(to: CGPoint(x: inward * o, y: len / 2)); path.addLine(to: CGPoint(x: inward * o, y: -len / 2))
            } else {
                path.move(to: CGPoint(x: -len / 2, y: o)); path.addLine(to: CGPoint(x: len / 2, y: o))
            }
        }
        let n = SKShapeNode(path: path)
        n.strokeColor = NSColor(calibratedRed: 0.62, green: 0.64, blue: 0.68, alpha: 0.95)
        n.lineWidth = pixel ? 3 : 1.3
        n.lineCap = .round
        n.isAntialiased = !pixel
        n.position = pixel ? CGPoint(x: (p.x / 3).rounded() * 3, y: (p.y / 3).rounded() * 3) : p
        n.zPosition = 9
        addChild(n)
        n.run(.sequence([.wait(forDuration: 1.2), .fadeOut(withDuration: 1.6), .removeFromParent()]))
    }

    // MARK: отрисовка кота

    func paint(_ c: Cat, _ dt: Double) {
        var x = c.x, y = c.y
        if c.hoverT > 0.9 && c.state != .sleep { x += CGFloat(sin(clock * 55)) * 0.7 }
        if pixel { x = (x / 3).rounded() * 3; y = (y / 3).rounded() * 3 }
        c.node.position = CGPoint(x: x, y: y)
        c.node.xScale = c.facing
        let swing = c.state == .drag ? max(-0.5, min(0.5, -(mouse.x - prevMouse.x) * 0.03)) : 0
        c.node.zRotation += (swing - c.node.zRotation) * 0.25
        c.texT -= dt
        guard c.texT <= 0 else { return }
        c.texT = 1.0 / 12
        var p = Pose()
        p.t = c.chase != nil || c.run ? c.anim * 1.9 : c.anim
        switch c.state {
        case .walk: p.kind = .side; p.walk = 1
        case .stand:
            p.kind = .side
            if c.nuzzle { p.nuzzle = CGFloat(sin(min(1, c.t / c.dur) * .pi)); if p.nuzzle > 0.5 { p.eyes = .closed } }
        case .sit:
            p.kind = .sit; p.snow = c.headSnow
            if c.sub == .swat { p.pawLift = CGFloat(sin(min(1, c.subT / 0.9) * .pi)); p.eyes = .wide }
            if c.sub == .sneeze { p.headDip = CGFloat(sin(min(1, c.subT / 0.7) * .pi)); p.eyes = .closed }
            if c.sub == .yawn {
                // сначала смотрит на курсор, потом зевает: рот открывается, держится и закрывается
                let v = (c.subT - c.stare) / Self.yawnLen
                func ease(_ x: Double) -> CGFloat { let x = max(0, min(1, x)); return CGFloat(x * x * (3 - 2 * x)) }
                if v > 0 { p.yawn = v < 0.3 ? ease(v / 0.3) : (v < 0.7 ? 1 : ease((1 - v) / 0.3)) }
                p.gaze = max(-1, min(1, (mouse.x - c.x) / 300)) * c.facing * (1 - p.yawn)
            }
        case .sitBack: p.kind = .sitBack; p.headTurn = c.headTurn; p.snow = c.headSnow
        case .sleep: p.kind = .curl; p.snow = c.snowCover
        case .seal: p.kind = .seal; p.grab = c.grabT > 0 ? 1 : 0; p.eyes = c.grabT > 0 ? .happy : .wide
        case .lounge: p.kind = .lounge
        case .loaf: p.kind = .loaf
        case .crouch: p.kind = .side; p.crouch = 1; p.eyes = .wide
        case .jump, .fall: p.kind = .side; p.air = 1; p.eyes = .wide
        case .drag: p.kind = .side; p.air = 1; p.eyes = c.look.squint ? .normal : .wide
        case .shake: p.kind = .side; p.pawLift = 1
        case .stretch: p.kind = .side; p.stretch = CGFloat(sin(min(1, c.t / c.dur) * .pi)); p.eyes = .closed
        case .scratch: p.kind = .side; p.stretch = 0.8; p.scratch = 1; p.eyes = .closed
        case .scratchWall: p.kind = .wall; p.eyes = c.look.squint ? .normal : .wide
        }
        if p.eyes == .normal && c.sub != .yawn && c.anim.truncatingRemainder(dividingBy: 4.3) < 0.16 { p.eyes = .closed }
        if p.eyes == .normal, balls.contains(where: { $0.mode == .flying && abs($0.x - c.x) < 600 }) { p.eyes = .wide }
        if p.kind != .curl, c.grabT <= 0 {
            if c.hoverT > 0.9 { p.eyes = .happy } else if c.hoverT > 0.25 { p.eyes = .wide }
        }
        if c.happy > 0 && p.kind != .curl { p.eyes = .happy }
        let tex = SKTexture(cgImage: Art.render(c.look, style, p))
        tex.filteringMode = pixel ? .nearest : .linear
        c.node.texture = tex
    }

    // MARK: осуждающий взгляд

    func showJudge() {
        guard judge == nil, let look = (cats.first { $0.look.id == "tom" } ?? cats.first)?.look else { return }
        judgeLook = look
        let n = SKSpriteNode()
        n.size = CGSize(width: Art.canvas.width * 3, height: Art.canvas.height * 3)
        n.anchorPoint = CGPoint(x: 0.5, y: Art.ground / Art.canvas.height)
        n.zPosition = 30
        n.position = CGPoint(x: W - 230, y: -320)
        addChild(n)
        judge = n; judgeT = 0; lastJudge = clock
    }

    func stepJudge(_ dt: Double) {
        judgeCheck -= dt
        if judgeCheck <= 0 {
            judgeCheck = 20
            let hour = Calendar.current.component(.hour, from: Date())
            if Prefs.judge, (1..<5).contains(hour), clock - lastJudge > 900, idle < 60 { showJudge() }
        }
        guard let n = judge else { return }
        let before = judgeT
        judgeT += dt
        let total = 9.0
        let e: Double = judgeT < 1.2 ? judgeT / 1.2 : (judgeT > total - 1.2 ? max(0, (total - judgeT) / 1.2) : 1)
        let ease = CGFloat(e * e * (3 - 2 * e))
        n.position.y = -320 + 300 * ease
        if Int(before * 6) != Int(judgeT * 6) || n.texture == nil {
            var p = Pose(); p.kind = .face
            p.eyes = judgeT.truncatingRemainder(dividingBy: 3.1) < 0.15 ? .closed : .normal
            let tex = SKTexture(cgImage: Art.render(judgeLook, style, p))
            tex.filteringMode = pixel ? .nearest : .linear
            n.texture = tex
        }
        if judgeT >= total { n.removeFromParent(); judge = nil }
    }

    // MARK: сценки по запросу (для проверки)

    func demo(_ name: String) {
        if name == "judge" { showJudge(); return }
        if let k = Meet.Kind(rawValue: name) { if meet != nil { endMeet() }; startMeet(k); return }
        if name == "snowman" {
            guard let c = cats.first, let sf = surface(c.surf) else { return }
            let x = c.x + 90 <= W - 40 ? c.x + 90 : c.x - 90
            let sm = Snowman(surf: sf.id, rel: x - sf.x0, radii: [20, 14, 10])
            sm.born = clock
            addChild(sm.node); snowmen.append(sm)
            let b = Ball(); b.r = 6; b.x = c.x - 60; b.y = c.y + 120; b.mode = .flying; b.vx = 60
            addChild(b.node); balls.append(b)
            return
        }
        for c in cats where c.state != .jump && c.state != .fall && c.state != .drag {
            switch name {
            case "seal": begin(c, .seal, 14)
            case "window": begin(c, .sitBack, 14)
            case "lounge": begin(c, .lounge, 14)
            case "loaf":
                if let s = surfaces.first(where: { $0.id > 0 && $0.id < 1_000_000_000 && $0.catOK }), let g = s.segs.first, c === cats.first(where: { $0.state != .jump && $0.state != .fall }) {
                    jump(c, to: s, x: (g.lowerBound + g.upperBound) / 2, after: (.loaf, 16))
                } else { begin(c, .loaf, 14) }
            case "hunt": startHunt(c)
            case "sleep": c.napIdle = false; begin(c, .sleep, 25)
            case "sneeze": begin(c, .sit, 4); startSub(c, .sneeze)
            case "yawn": begin(c, .sit, 7); startSub(c, .yawn); c.stare = 2.5
            case "swat": begin(c, .sit, 4); startSub(c, .swat)
            case "shake": c.targetRel = c.rel; begin(c, .shake, 1.5)
            case "scratch": begin(c, .scratch, 6)
            case "wall":
                if let s = surface(c.surf), let seg = s.seg(at: c.x, tol: 6), let w = wallSpot(c, s, seg, maxDist: 1e9) { goWall(c, s, w, dur: 7) }
                else { begin(c, .scratch, 6) }
            default: break
            }
        }
    }
}
