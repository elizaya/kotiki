import AppKit
import SpriteKit

// Игра со снегом: стряхивание курсором, снежки (с зажатой клавишей) и снеговики.

final class Ball {
    enum Mode { case held, flying, rolling, resting }
    var mode = Mode.held
    var x: CGFloat = 0
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var r: CGFloat = 4
    var surf = -2
    var rel: CGFloat = 0
    var thrown = false
    var bounces = 0
    var catchTried = false
    var restT = 0.0
    var dead = false
    var key = ""
    let node = SKSpriteNode()
}

final class Snowman {
    var surf: Int
    var rel: CGFloat
    var radii: [CGFloat]
    var x: CGFloat = 0
    var y: CGFloat = 0
    var dirty = true
    var lostT = 0.0
    var born = 0.0
    var doom = Double.random(in: 45...120)
    var doomed = false
    let node = SKSpriteNode()
    init(surf: Int, rel: CGFloat, radii: [CGFloat]) {
        self.surf = surf; self.rel = rel; self.radii = radii
        node.zPosition = 8
    }
    var topY: CGFloat { SnowArt.centers(radii).last! + radii.last! * 0.75 }
    var height: CGFloat { SnowArt.centers(radii).last! + radii.last! }
}

enum Goal { case none, knock(Snowman), sitBy, napBy, wall(CGFloat, Double) }

enum SnowArt {
    static func centers(_ radii: [CGFloat]) -> [CGFloat] {
        var out: [CGFloat] = []
        var cy: CGFloat = 0
        for (i, r) in radii.enumerated() {
            cy = i == 0 ? r * 0.92 : cy + radii[i - 1] * 0.78 + r * 0.72
            out.append(cy)
        }
        return out
    }

    /// Рисует ком или стопку комьев; три кома — снеговик с лицом.
    static func stack(_ radii: [CGFloat], pixel: Bool) -> (SKTexture, CGSize) {
        let face = radii.count == 3
        let cs = centers(radii)
        let pad: CGFloat = face ? 18 : 3
        let w = ceil((2 * radii.max()! + 2 * pad) / 3) * 3
        let h = ceil((cs.last! + radii.last! + 5) / 3) * 3
        let k: CGFloat = pixel ? 1.0 / 3 : 2
        let pw = Int(w * k), ph = Int(h * k)
        let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setShouldAntialias(!pixel)
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: w / 2, y: 3)
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: CGColor) {
            ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        func line(_ a: CGPoint, _ b: CGPoint, _ c: CGColor) {
            ctx.setStrokeColor(c); ctx.setLineWidth(pixel ? 3 : 1.8); ctx.setLineCap(.round)
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        }
        if face {
            let c = cs[1], r = radii[1], brown = rgb(0x6b4a2f)
            for s: CGFloat in [-1, 1] {
                let tip = CGPoint(x: s * (r + 13), y: c + r * 0.3 + 10)
                line(CGPoint(x: s * r * 0.7, y: c + r * 0.2), tip, brown)
                line(CGPoint(x: s * (r + 8), y: c + r * 0.3 + 6), CGPoint(x: s * (r + 13), y: c + r * 0.3 + 3), brown)
            }
        }
        for (i, r) in radii.enumerated() {
            circle(0, cs[i], r, rgb(0xd3deeb))
            circle(-r * 0.07, cs[i] + r * 0.09, r * 0.9, rgb(0xffffff))
            if !pixel {
                ctx.setStrokeColor(rgb(0xb3c4d8)); ctx.setLineWidth(1)
                ctx.strokeEllipse(in: CGRect(x: -r, y: cs[i] - r, width: 2 * r, height: 2 * r))
            }
        }
        if face {
            let c = cs[2], r = radii[2], dark = rgb(0x2b2d33)
            let e = max(pixel ? 1.6 : 1.3, r * 0.13)
            for s: CGFloat in [-1, 1] {
                if pixel { ctx.setFillColor(dark); ctx.fill(CGRect(x: s * r * 0.38 - 1.5, y: c + r * 0.2 - 1.5, width: 3, height: 3)) }
                else { circle(s * r * 0.38, c + r * 0.22, e, dark) }
            }
            ctx.setFillColor(rgb(0xf08a24))
            ctx.beginPath()
            ctx.addLines(between: [CGPoint(x: 0, y: c + r * 0.08), CGPoint(x: 0, y: c - r * 0.22), CGPoint(x: r * 1.15, y: c - r * 0.1)])
            ctx.closePath(); ctx.fillPath()
            let m = cs[1], mr = radii[1]
            for dy in [mr * 0.35, -mr * 0.15] {
                if pixel { ctx.setFillColor(dark); ctx.fill(CGRect(x: -1.5, y: m + dy - 1.5, width: 3, height: 3)) }
                else { circle(0, m + dy, max(1.2, mr * 0.09), dark) }
            }
        }
        if pixel { Art.outline(ctx, pw, ph, rgb(0x9fb2c8)) }
        let tex = SKTexture(cgImage: ctx.makeImage()!)
        tex.filteringMode = pixel ? .nearest : .linear
        return (tex, CGSize(width: w, height: h))
    }
}

extension OverlayScene {
    var playKeyDown: Bool {
        guard Prefs.play else { return false }
        let keys: [NSEvent.ModifierFlags] = [.option, .shift, .command]
        return NSEvent.modifierFlags.contains(keys[max(0, min(2, Prefs.playKey))])
    }

    func mouseVelocity() -> CGPoint {
        guard let last = trail.last, let first = trail.first(where: { clock - $0.1 < 0.11 }), last.1 - first.1 > 0.01 else { return .zero }
        let t = CGFloat(last.1 - first.1)
        return CGPoint(x: (last.0.x - first.0.x) / t, y: (last.0.y - first.0.y) / t)
    }

    func clearPlay() {
        for b in balls { b.node.removeFromParent() }
        for s in snowmen { s.node.removeFromParent() }
        balls.removeAll(); snowmen.removeAll(); held = nil
        for c in cats { c.chase = nil; c.goal = .none }
    }

    func restylePlay() {
        ballTex.removeAll()
        for b in balls { b.key = "" }
        for s in snowmen { s.dirty = true }
    }

    // MARK: захват мышью

    func tryGrab(_ p: CGPoint) -> Bool {
        guard Prefs.play, playKeyDown, held == nil else { return false }
        if let b = balls.first(where: { $0.mode != .flying && hypot(p.x - $0.x, p.y - $0.y) < $0.r + 7 }) {
            b.mode = .held; held = b
            for c in cats where c.chase === b { c.chase = nil }
            return true
        }
        // разобрать снеговика: снять верхний ком
        if let sm = snowmen.first(where: { !$0.node.isHidden && abs(p.x - $0.x) < $0.radii[0] + 4 && p.y > $0.y && p.y < $0.y + $0.height + 4 }) {
            let b = Ball()
            b.r = sm.radii.removeLast(); b.x = p.x; b.y = p.y; sm.born = clock
            addChild(b.node); balls.append(b); held = b
            sm.dirty = true
            if sm.radii.count == 1 {
                let base = Ball()
                base.r = sm.radii[0]; base.mode = .resting; base.surf = sm.surf; base.rel = sm.rel; base.x = sm.x; base.y = sm.y + base.r * 0.9
                addChild(base.node); balls.append(base)
                sm.node.removeFromParent()
            }
            return true
        }
        for s in surfaces {
            guard let pile = piles[s.id], s.seg(at: p.x) != nil else { continue }
            let h = pile.height(at: p.x - s.x0)
            if h > 1.5, p.y > s.y - 6, p.y < s.y + h + 12 {
                let b = Ball()
                b.x = p.x; b.y = p.y; b.r = 4
                b.node.zPosition = 12
                addChild(b.node); balls.append(b); held = b
                if balls.count > 14, let old = balls.first(where: { $0.mode == .resting }) { shatter(old) }
                return true
            }
        }
        return false
    }

    func release(_ b: Ball, _ v: CGPoint) {
        held = nil
        let sp = hypot(v.x, v.y)
        if sp > 300 {
            let k = min(1, 1700 / sp)
            b.vx = v.x * k; b.vy = v.y * k; b.thrown = true
        } else { b.vx = 0; b.vy = 0; b.thrown = false }
        b.mode = .flying; b.bounces = 0; b.catchTried = false
    }

    // MARK: шаг

    func stepPlay(_ dt: Double) {
        let d = CGFloat(dt)
        let down = NSEvent.pressedMouseButtons & 1 != 0
        let vel = mouseVelocity()
        let sp = hypot(vel.x, vel.y)

        // стряхивание
        if Prefs.play, held == nil, !down, sp > 450 {
            let x0 = min(prevMouse.x, mouse.x), x1 = max(prevMouse.x, mouse.x)
            let ym = (prevMouse.y + mouse.y) / 2
            if x1 - x0 < 400 {
                for s in surfaces {
                    guard let p = piles[s.id], ym > s.y - 5, ym < s.y + CGFloat(s.cap) + 8 else { continue }
                    var removed: Float = 0
                    var x = x0 - 6
                    while x <= x1 + 6 {
                        if s.seg(at: x) != nil, ym < s.y + p.height(at: x - s.x0) + 8 { removed += p.take(at: x - s.x0, 0.85) }
                        x += Pile.col
                    }
                    if removed > 2 { puff(at: CGPoint(x: mouse.x, y: s.y + 6), min(8, Int(removed / 4) + 1)) }
                }
            }
        }

        // ком в руке
        if let b = held {
            if !down { release(b, vel) } else {
                b.x = mouse.x; b.y = mouse.y
                let near = surfaces.filter { $0.seg(at: b.x) != nil && mouse.y > $0.y - 20 && mouse.y < $0.y + CGFloat($0.cap) + b.r + 14 }
                    .min { abs($0.y - mouse.y) < abs($1.y - mouse.y) }
                if let s = near, let pile = piles[s.id] {
                    let moved = abs(mouse.x - prevMouse.x)
                    let frac = Float(min(0.7, Double(moved) * 0.06 + dt * 1.2))
                    var got: Float = 0
                    var x = b.x - b.r * 0.7
                    while x <= b.x + b.r * 0.7 {
                        if s.seg(at: x) != nil { got += pile.take(at: x - s.x0, frac) }
                        x += Pile.col
                    }
                    if b.r < 28 { b.r = min(28, sqrt(b.r * b.r + CGFloat(got) * Pile.col * 0.9 / .pi)) }
                    b.y = s.y + pile.height(at: b.x - s.x0) * 0.5 + b.r * 0.9
                }
            }
        }

        // физика
        for b in balls where !b.dead {
            switch b.mode {
            case .held: break
            case .flying: fly(b, d)
            case .rolling, .resting:
                guard let s = surface(b.surf), s.seg(at: s.x0 + b.rel, tol: 2) != nil else { b.mode = .flying; b.vy = 0; break }
                if b.mode == .rolling {
                    b.rel += b.vx * d
                    b.vx -= (b.vx > 0 ? 1 : -1) * 260 * d
                    if abs(b.vx) < 20 { b.vx = 0; b.mode = .resting; b.restT = 0 }
                } else {
                    b.restT += dt
                    if b.r < 8 && b.restT > 25 { shatter(b); break }
                }
                b.x = s.x0 + b.rel; b.y = s.y + b.r * 0.9
            }
        }
        balls.removeAll { $0.dead }

        // снеговики
        for sm in snowmen {
            // окно могло на миг пропасть из списка или оказаться закрытым другим — не ломаем сразу
            guard let s = surface(sm.surf) else {
                sm.lostT += dt
                // окно закрыли — снеговик переезжает на то, что ниже, а не рушится
                if sm.lostT > 1.5 {
                    let below = surfaces.filter { $0.seg(at: sm.x) != nil && $0.y <= sm.y }.max { $0.y < $1.y }
                        ?? surfaces.filter { $0.seg(at: sm.x) != nil }.min { $0.y < $1.y }
                    if let b = below { sm.surf = b.id; sm.rel = sm.x - b.x0; sm.lostT = 0 } else if sm.lostT > 10 { collapse(sm) }
                }
                continue
            }
            sm.lostT = 0
            sm.node.isHidden = s.seg(at: s.x0 + sm.rel, tol: 2) == nil
            sm.x = s.x0 + sm.rel; sm.y = s.y
            if sm.dirty {
                let (t, size) = SnowArt.stack(sm.radii, pixel: pixel)
                sm.node.texture = t; sm.node.size = size
                sm.node.anchorPoint = CGPoint(x: 0.5, y: 3 / size.height)
                sm.dirty = false
            }
            sm.node.position = pixel ? CGPoint(x: (sm.x / 3).rounded() * 3, y: (sm.y / 3).rounded() * 3) : CGPoint(x: sm.x, y: sm.y)
        }
        snowmen.removeAll { $0.node.parent == nil }

        // коты и снежки
        for c in cats {
            c.ballCD -= dt
            guard c.chase == nil, c.ballCD <= 0, c.sub == .none, c.meet == nil, c.look.can("snow"), [.walk, .stand, .sit, .sitBack, .loaf, .lounge].contains(c.state) else { continue }
            if case .none = c.goal {} else { continue }
            let near = balls.filter { ($0.mode == .rolling || $0.mode == .resting) && $0.r < 12 && $0.surf == c.surf && abs($0.x - c.x) < 600 && $0.restT < 20 && pathFree(c, to: $0.x) }
                .min { abs($0.x - c.x) < abs($1.x - c.x) }
            if let b = near { begin(c, .walk); c.chase = b; c.targetRel = b.rel }
        }

        // отрисовка комьев
        for b in balls {
            let key = "\(Int(b.r.rounded()))-\(pixel)"
            if b.key != key {
                b.key = key
                let (t, size): (SKTexture, CGSize)
                if let e = ballTex[key] { (t, size) = e } else { (t, size) = SnowArt.stack([b.r.rounded()], pixel: pixel); ballTex[key] = (t, size) }
                b.node.texture = t; b.node.size = size
                b.node.anchorPoint = CGPoint(x: 0.5, y: (3 + b.r.rounded() * 0.92) / size.height)
            }
            b.node.zPosition = b.mode == .held ? 25 : 12
            b.node.position = pixel ? CGPoint(x: (b.x / 3).rounded() * 3, y: (b.y / 3).rounded() * 3) : CGPoint(x: b.x, y: b.y)
        }
        prevMouse = mouse
    }

    func fly(_ b: Ball, _ d: CGFloat) {
        b.vy -= 1400 * d
        let py = b.y
        b.x += b.vx * d; b.y += b.vy * d
        if b.x < b.r { b.x = b.r; b.vx = abs(b.vx) * 0.5 }
        if b.x > W - b.r { b.x = W - b.r; b.vx = -abs(b.vx) * 0.5 }
        let speed = hypot(b.vx, b.vy)

        for c in cats {
            let s = c.look.size
            let touching = abs(b.x - c.x) < 30 * s + b.r && b.y > c.y - b.r && b.y < c.y + 62 * s + b.r
            if touching {
                if c.state == .jump && c.catching { shatter(b); c.happy = 1.6; c.catching = false; heart(at: CGPoint(x: c.x, y: c.y + 62 * s)); return }
                if b.thrown && speed > 250 && c.state != .jump && c.state != .fall { hitCat(c, b); return }
            } else if b.thrown, !b.catchTried, c.ballCD <= 0, !c.busy, c.look.can("snow"), abs(b.x - c.x) < 150, b.y - c.y > 20, b.y - c.y < 180 {
                b.catchTried = true
                if Double.random(in: 0...1) < 0.45, let sf = surface(c.surf), let seg = sf.seg(at: c.x, tol: 6) {
                    let tx = min(max(b.x + b.vx * 0.25, seg.lowerBound + 20), max(seg.lowerBound + 20, seg.upperBound - 20))
                    jump(c, to: sf, x: tx, after: (.sit, 1.5), height: min(160, max(45, b.y - c.y + 15)))
                    c.jDur = 0.4; c.catching = true
                }
            }
        }
        guard b.vy < 0 else { return }

        // на снеговика или на другой ком
        for sm in snowmen where sm.radii.count < 3 {
            let top = sm.y + sm.topY
            if abs(b.x - sm.x) < sm.radii.last! * 0.9 + 4, py - b.r >= top - 4, b.y - b.r < top, b.r <= sm.radii.last! * 1.15 {
                sm.radii.append(b.r); sm.dirty = true; sm.born = clock
                puff(at: CGPoint(x: sm.x, y: top), 3)
                remove(b); return
            }
        }
        for base in balls where base !== b && !base.dead && base.mode == .resting && base.r >= 7 {
            let top = base.y + base.r * 0.8
            if abs(b.x - base.x) < base.r * 0.9 + 4, py - b.r >= top - 4, b.y - b.r < top, b.r <= base.r * 1.15 {
                let sm = Snowman(surf: base.surf, rel: base.rel, radii: [base.r, b.r])
                sm.born = clock
                addChild(sm.node); snowmen.append(sm)
                puff(at: CGPoint(x: base.x, y: top), 3)
                remove(base); remove(b)
                return
            }
        }
        // на поверхность
        for s in surfaces where s.seg(at: b.x) != nil {
            let top = s.y + (piles[s.id]?.height(at: b.x - s.x0) ?? 0) * 0.3
            guard py - b.r >= top - 1, b.y - b.r < top else { continue }
            let impact = -b.vy
            b.surf = s.id; b.rel = b.x - s.x0
            if b.thrown, b.bounces == 0, impact > 450, b.r < 14 {
                b.bounces = 1; b.vy = impact * 0.38; b.vx *= 0.7; b.y = top + b.r
                puff(at: CGPoint(x: b.x, y: top), 2)
                return
            }
            if b.thrown, b.r < 8, impact > 900 { shatter(b); return }
            b.vy = 0; b.restT = 0; b.y = s.y + b.r * 0.9
            b.mode = abs(b.vx) > 40 ? .rolling : .resting
            return
        }
        if b.y < -60 { remove(b) }
    }

    func remove(_ b: Ball) {
        b.dead = true
        b.node.removeFromParent()
        if held === b { held = nil }
        for c in cats where c.chase === b { c.chase = nil }
    }

    func shatter(_ b: Ball) {
        puff(at: CGPoint(x: b.x, y: b.y), 3 + Int(b.r / 2))
        if let s = surfaces.filter({ $0.seg(at: b.x) != nil && $0.y <= b.y + 2 }).max(by: { $0.y < $1.y }) {
            piles[s.id]?.add(at: b.x - s.x0, Float(b.r) * 1.5, cap: s.cap)
        }
        remove(b)
    }

    func collapse(_ sm: Snowman) {
        let cs = SnowArt.centers(sm.radii)
        for (i, r) in sm.radii.enumerated() { puff(at: CGPoint(x: sm.x, y: sm.y + cs[i]), 3 + Int(r / 3)) }
        if let s = surface(sm.surf) { for r in sm.radii { piles[s.id]?.add(at: sm.rel + CGFloat.random(in: -10...10), Float(r) * 1.5, cap: s.cap) } }
        sm.node.removeFromParent()
        for c in cats { if case .knock(let t) = c.goal, t === sm { c.goal = .none } }
    }

    // MARK: коты

    func hitCat(_ c: Cat, _ b: Ball) {
        shatter(b)
        if c.state == .sleep { wake(c); return }
        c.facing = mouse.x >= c.x ? 1 : -1
        if c.look.squint {
            begin(c, .sit, 3.5); startSub(c, .sneeze)
        } else if let s = surface(c.surf) {
            jump(c, to: s, x: c.x, after: (.stand, 0.4), height: 55)
            c.jDur = 0.4; c.ballCD = 0
        }
    }

    func arrive(_ c: Cat) {
        if let b = c.chase {
            bats += 1
            let dir = batDir(c)
            c.facing = dir
            b.mode = .flying; b.vx = dir * CGFloat.random(in: 240...380); b.vy = 150; b.thrown = false; b.bounces = 1
            b.r -= 0.5
            if b.r < 3.5 { shatter(b) }
            begin(c, .sit, 1.2); startSub(c, .swat)
            c.ballCD = 1.0
            return
        }
        switch c.goal {
        case .knock(let sm):
            c.facing = sm.x >= c.x ? 1 : -1
            begin(c, .sit, 2.4); startSub(c, .swat)
        case .sitBy: begin(c, .sit, Double.random(in: 6...12))
        case .napBy: dozeOff(c, Double.random(in: 20...40))
        case .wall(let dir, let dur): c.facing = dir; begin(c, .scratchWall, dur)
        case .none: next(c)
        }
    }

    /// Куда отбить снежок: другому коту, к курсору (если им шевелят рядом) или туда, где больше места.
    func batDir(_ c: Cat) -> CGFloat {
        if let o = cats.first(where: { $0 !== c && $0.surf == c.surf && !$0.busy && abs($0.x - c.x) > 40 }) { return o.x > c.x ? 1 : -1 }
        if idle < 3, abs(mouse.x - c.x) < 700, abs(mouse.y - c.y) < 400 { return mouse.x >= c.x ? 1 : -1 }
        if let s = surface(c.surf), let seg = s.seg(at: c.x, tol: 6) { return seg.upperBound - c.x > c.x - seg.lowerBound ? 1 : -1 }
        return Bool.random() ? 1 : -1
    }

    /// Снеговик «созрел»: простоял своё время, и коты могут его ломать.
    func ripe(_ sm: Snowman) -> Bool { sm.doomed || clock - sm.born > sm.doom }

    func playSwat(_ c: Cat) {
        guard case .knock(let sm) = c.goal else { return }
        c.goal = .none
        guard sm.node.parent != nil else { return }
        knocks += 1
        sm.doomed = true
        // последний ком кот просто разваливает
        if sm.radii.count <= 1 { collapse(sm); return }
        let r = sm.radii.removeLast()
        sm.dirty = true
        let b = Ball()
        b.r = r; b.x = sm.x; b.y = sm.y + sm.topY + r
        b.mode = .flying; b.vx = c.facing * 230; b.vy = 280; b.thrown = true; b.bounces = 1
        addChild(b.node); balls.append(b)
        puff(at: CGPoint(x: b.x, y: b.y), 4)
    }

    /// Дела у снеговика: посидеть рядом, поспать под боком, а Том иногда сбивает голову.
    func playNext(_ c: Cat, _ s: Surface) -> Bool {
        guard Prefs.play else { return false }
        let breaks = Prefs.tomBreaks && c.look.can("knock")
        let a = [0.5, 1.0, 1.9][max(0, min(2, Prefs.antics))]
        // кот сам лепит себе снежок и гоняет его — и в одиночку, и вдвоём
        let hasSnow = (piles[s.id]?.height(at: c.rel) ?? 0) > 2
        if hasSnow, c.look.can("snow"), Double.random(in: 0...1) < 0.2 * a,
           !balls.contains(where: { $0.r < 12 && $0.surf == c.surf && abs($0.x - c.x) < 600 }) {
            let dir = batDir(c)
            c.facing = dir
            _ = piles[s.id]?.take(at: c.rel + dir * 12, 0.8)
            let b = Ball()
            b.r = 6.5; b.x = c.x + dir * 18; b.y = c.y + 8
            b.mode = .flying; b.vx = dir * CGFloat.random(in: 220...340); b.vy = 170; b.bounces = 1
            addChild(b.node); balls.append(b)
            begin(c, .sit, 1.2); startSub(c, .swat)
            c.ballCD = 1.0
            selfPlays += 1
            return true
        }
        // Том идёт к снеговику даже с другого окна
        if breaks, Double.random(in: 0...1) < 0.3 * a,
           let far = snowmen.first(where: { $0.surf != c.surf && ripe($0) && !$0.node.isHidden }),
           let fs = surface(far.surf), fs.catOK {
            let side: CGFloat = c.x < far.x ? -1 : 1
            var tx = far.x + side * (far.radii[0] + 24)
            if fs.seg(at: tx) == nil { tx = far.x - side * (far.radii[0] + 24) }
            if fs.seg(at: tx) != nil { jump(c, to: fs, x: tx, after: (.stand, 0.3)); return true }
        }
        guard let sm = snowmen.first(where: { $0.surf == c.surf && !$0.node.isHidden && abs($0.x - c.x) < 1200 }) else { return false }
        let r = Double.random(in: 0...1)
        let goal: Goal
        if breaks && ripe(sm) && r < 0.6 * a { goal = .knock(sm) }
        else if r > 0.85 { goal = c.look.squint || Bool.random() ? .sitBy : .napBy }
        else { return false }
        let side: CGFloat = c.x < sm.x ? -1 : 1
        var tx = sm.x + side * (sm.radii[0] + 24)
        if s.seg(at: tx) == nil { tx = sm.x - side * (sm.radii[0] + 24) }
        guard s.seg(at: tx) != nil, pathFree(c, to: tx) else { return false }
        c.targetRel = tx - s.x0
        begin(c, .walk)
        c.goal = goal
        return true
    }
}
