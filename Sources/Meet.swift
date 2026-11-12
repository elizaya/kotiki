import AppKit
import SpriteKit

// Встречи котов. Обычно каждый сам по себе, но иногда один подходит к другому:
// обнюхаться, посидеть рядом, поспать бок о бок или побегать в догонялки.
// Встреча ведёт двух котов через обычные состояния (идёт, сидит, прыгает),
// а когда очередное состояние заканчивается, next() зовёт meetNext().

final class Meet {
    enum Kind: String { case greet, together, nap, chase }
    let kind: Kind
    /// a подходит, b ждёт
    let a: Cat, b: Cat
    var phase = 0
    /// сколько идёт встреча и сколько — текущая фаза
    var t = 0.0
    var pt = 0.0
    /// на каком расстоянии коты встают друг от друга
    var dist: CGFloat = 60
    /// если задано — насколько близко им можно быть (вместо обычного зазора)
    var tight: CGFloat?
    /// b спал, когда к нему пошли
    var asleep = false
    /// запущена из меню: без отказов
    var forced = false
    var hearted = false
    // догонялки
    var chaser: Cat, runner: Cat
    var legs = 0
    var pounced = false

    init(_ kind: Kind, _ a: Cat, _ b: Cat) {
        self.kind = kind; self.a = a; self.b = b
        chaser = a; runner = b
    }
}

extension OverlayScene {
    /// Насколько нос кота, стоящего боком, выдаётся вперёд от его центра.
    func reach(_ c: Cat) -> CGFloat { (c.look.bodyLen * 0.72 + 3 + c.look.headRX) * c.look.size }

    func stepMeet(_ dt: Double) {
        if let m = meet {
            m.t += dt; m.pt += dt
            let both = [m.a, m.b]
            let broken = both.contains { c in
                !cats.contains { $0 === c } || c.state == .drag || c.state == .fall || c.chase != nil || c === grabCat
            }
            let resting = (m.kind == .nap || m.kind == .together) && m.phase == 1
            if broken || (!resting && m.t > 40) { endMeet(); return }
            if m.kind == .greet, m.phase == 1, !m.hearted, m.pt > 0.9 {
                m.hearted = true
                heart(at: CGPoint(x: (m.a.x + m.b.x) / 2, y: max(m.a.y, m.b.y) + 58 * max(m.a.look.size, m.b.look.size)))
            }
            return
        }
        guard cats.count > 1, idle < 240 else { return }
        meetCD -= dt
        guard meetCD <= 0 else { return }
        let a = [0.5, 1.0, 1.9][max(0, min(2, Prefs.antics))]
        meetCD = startMeet(nil) ? Double.random(in: 80...200) / a : 6
    }

    func endMeet() {
        guard let m = meet else { return }
        meet = nil
        for c in [m.a, m.b] {
            c.meet = nil; c.run = false; c.nuzzle = false
            // кто ждал другого — больше не ждёт
            if c.dur - c.t > 50, c.state != .sleep { c.dur = c.t + Double.random(in: 1...2.5) }
        }
    }

    @discardableResult
    func startMeet(_ force: Meet.Kind?) -> Bool {
        guard meet == nil, cats.count > 1 else { return false }
        func free(_ c: Cat) -> Bool {
            // из меню сценку можно запустить, чем бы кот ни был занят, лишь бы стоял на опоре
            let ok: [CatState] = force != nil ? [.walk, .stand, .sit, .sitBack, .lounge, .loaf, .seal, .scratch, .scratchWall, .shake, .stretch]
                : [.walk, .stand, .sit, .sitBack, .lounge, .loaf]
            guard ok.contains(c.state), c.chase == nil, c.hoverT <= 0, c !== grabCat else { return false }
            if case .none = c.goal { return true }
            return false
        }
        // кто общительнее, тот чаще подходит первым
        let starters = cats.filter(free)
        var r = Double.random(in: 0..<max(0.001, starters.reduce(0) { $0 + $1.look.social + 0.02 }))
        guard let a = starters.first(where: { r -= $0.look.social + 0.02; return r < 0 }) ?? starters.first else { return false }
        if force == nil, Double.random(in: 0...1) > 0.25 + a.look.social * 1.5 { return false }
        let others = cats.filter { $0 !== a && (free($0) || ($0.state == .sleep && !$0.napIdle && (force ?? .nap) == .nap)) }
        guard let b = others.randomElement() else { return false }

        let kind: Meet.Kind
        if let f = force { kind = f }
        else if b.state == .sleep { kind = .nap }
        else {
            let act = a.look.activity
            let opts: [(Meet.Kind, Double)] = [(.greet, 3), (.together, snowing ? 3 : 2), (.nap, 1.2 * (1.5 - act)), (.chase, 2.4 * (0.4 + act))]
            var k = Double.random(in: 0..<opts.reduce(0) { $0 + $1.1 })
            kind = opts.first(where: { k -= $0.1; return k < 0 })?.0 ?? .greet
        }
        let m = Meet(kind, a, b)
        m.forced = force != nil
        m.asleep = b.state == .sleep
        let sizes = a.look.size + b.look.size
        switch kind {
        case .greet: m.dist = reach(a) + reach(b) + 3
        case .together: m.dist = 27 * sizes; m.tight = m.dist - 5
        case .nap: m.dist = 26 * sizes; m.tight = m.dist - 5
        case .chase: m.dist = place(a, by: b, 170) != nil ? 170 : gap(a, b) + 20
        }
        guard place(a, by: b, m.dist) != nil else { return false }
        meet = m; a.meet = m; b.meet = m
        meets += 1
        if !m.asleep { hold(b, m) }
        meetNext(a)
        return true
    }

    /// Кот ждёт, пока к нему подойдут. Лежащий и сидящий спиной остаются как были.
    func hold(_ c: Cat, _ m: Meet) {
        let o = c === m.a ? m.b : m.a
        if [.sitBack, .lounge, .loaf].contains(c.state), m.kind != .greet, m.kind != .chase { c.dur = c.t + 99; return }
        c.facing = o.x >= c.x ? 1 : -1
        begin(c, .sit, 99)
    }

    /// Где коту c встать рядом с o на расстоянии d: с той стороны, где он уже стоит, если там есть место.
    func place(_ c: Cat, by o: Cat, _ d: CGFloat) -> CGFloat? {
        guard let p = spot(o), let s = surface(o.state == .jump ? o.jSurf : o.surf), let seg = s.seg(at: p.x, tol: 6) else { return nil }
        let side: CGFloat = c.x >= p.x ? 1 : -1
        for sd in [side, -side] {
            let x = p.x + sd * d
            if x >= seg.lowerBound + 16 && x <= seg.upperBound - 16 { return x }
        }
        return nil
    }

    /// Ведёт кота c к o на расстояние d. true — уже на месте, false — в пути, nil — встать негде.
    func approach(_ c: Cat, _ o: Cat, _ d: CGFloat, run: Bool = false) -> Bool? {
        guard let p = spot(o), let os = surface(o.state == .jump ? o.jSurf : o.surf), let x = place(c, by: o, d) else { return nil }
        let here = surface(c.surf)?.seg(at: c.x, tol: 6)
        if c.surf == os.id, let seg = here, seg.contains(x) {
            if abs(x - c.x) < 6 { c.facing = p.x >= c.x ? 1 : -1; return true }
            if (x - p.x) * (c.x - p.x) < 0 {
                // место только по другую сторону — перепрыгиваем
                jump(c, to: os, x: x, after: nil)
            } else {
                c.targetRel = x - os.x0
                begin(c, .walk)
                c.goal = .none; c.run = run
            }
        } else {
            // с другого окна прыгаем чуть поодаль и доходим пешком
            var jx = x
            let far = x + (x >= p.x ? 1 : -1) * 70
            if !run, let seg = os.seg(at: x, tol: 6), far >= seg.lowerBound + 20, far <= seg.upperBound - 20 { jx = far }
            jump(c, to: os, x: jx, after: nil)
        }
        return false
    }

    /// Кот закончил очередное действие — решаем, что дальше по сценарию встречи.
    func meetNext(_ c: Cat) {
        guard let m = meet, c.meet === m else { c.meet = nil; next(c); return }
        let o = c === m.a ? m.b : m.a
        func quit() { endMeet(); next(c) }
        switch (m.kind, m.phase) {
        case (.chase, 1):
            guard c === m.a else { hold(c, m); return }
            // прыжок на то место, где сидел второй, — а тот уже удирает
            guard let s = surface(o.surf) else { quit(); return }
            let ox = o.x
            m.phase = 2; m.pt = 0; m.legs = Int.random(in: 2...3)
            flee(o, from: c, m)
            jump(c, to: s, x: ox, after: nil, height: 38)
            c.jDur = 0.45
        case (.chase, 2):
            if c === m.runner {
                // добежал — оборачивается и ждёт
                c.facing = o.x >= c.x ? 1 : -1
                begin(c, .sit, 99)
                return
            }
            if !m.pounced {
                // прыгнул и промахнулся: секунду соображает, куда тот делся
                m.pounced = true
                begin(c, .stand, 0.5)
                return
            }
            let near = c.surf == o.surf && o.state != .jump && abs(c.x - o.x) < gap(c, o) + 40
            if near {
                // догнал
                c.facing = o.x >= c.x ? 1 : -1
                m.legs -= 1
                if m.legs <= 0 {
                    for k in [c, o] { begin(k, .sit, Double.random(in: 2...4)); k.happy = 1.5 }
                    endMeet()
                } else {
                    // меняются: догнавший убегает, второй чуть медлит и бежит за ним
                    m.runner = c; m.chaser = o
                    o.facing = c.x >= o.x ? 1 : -1
                    begin(o, .stand, 0.6)
                    flee(c, from: o, m)
                }
            } else {
                switch approach(c, o, gap(c, o) + 8, run: true) {
                case nil: quit()
                case true?: begin(c, .stand, 0.3)
                case false?: break
                }
            }
        case (_, 0):
            guard c === m.a else {
                // b сам закончил своё занятие (или проснулся) раньше, чем к нему подошли
                if m.asleep { quit() } else { hold(c, m) }
                return
            }
            switch approach(c, o, m.dist) {
            case nil: quit()
            case false?: break
            case true?: arrived(c, o, m)
            }
        default:
            // сценка доиграна
            if m.kind == .greet {
                for k in [m.a, m.b] { begin(k, .sit, Double.random(in: 2...4)); k.happy = 1.6 }
                endMeet()
            } else { quit() }
        }
    }

    /// Кот a подошёл к b вплотную.
    func arrived(_ a: Cat, _ b: Cat, _ m: Meet) {
        m.phase = 1; m.pt = 0
        if !m.asleep { b.facing = a.x >= b.x ? 1 : -1 }
        switch m.kind {
        case .greet:
            if !m.forced, Double.random(in: 0...1) < (1 - b.look.social) * 0.45 {
                // не в настроении: отворачивается, а гость растерянно садится
                begin(b, .sitBack, Double.random(in: 4...7))
                begin(a, .sit, 2.2)
                endMeet()
            } else {
                for k in [a, b] { begin(k, .stand, 1.9); k.nuzzle = true }
            }
        case .together:
            let d = Double.random(in: 10...16)
            begin(a, .sitBack, d)
            if b.state == .sitBack { b.dur = b.t + d + 1.5 } else { begin(b, .sitBack, d + 1.5) }
        case .nap:
            // головами друг к другу
            let d = Double.random(in: 25...45)
            a.facing = b.x >= a.x ? -1 : 1
            dozeOff(a, d)
            if !m.asleep {
                b.facing = a.x >= b.x ? -1 : 1
                dozeOff(b, d + Double.random(in: 0...6))
            }
        case .chase:
            begin(a, .crouch, 1.0)
        }
    }

    /// Убегает от другого кота: по своей поверхности, а если бежать некуда — прыжком на другую.
    func flee(_ r: Cat, from ch: Cat, _ m: Meet) {
        guard let s = surface(r.surf), let seg = s.seg(at: r.x, tol: 6) else { return }
        let dir: CGFloat = r.x >= ch.x ? 1 : -1
        let edge = dir > 0 ? seg.upperBound - 30 : seg.lowerBound + 30
        let room = (edge - r.x) * dir
        func runTo(_ tx: CGFloat) {
            r.targetRel = tx - s.x0
            begin(r, .walk)
            r.goal = .none; r.run = true
        }
        if room > 130, Double.random(in: 0...1) < 0.65 {
            runTo(r.x + dir * min(room, CGFloat.random(in: 220...520)))
        } else if !randomJump(r) {
            if room > 40 { runTo(edge) } else { r.facing = -dir; begin(r, .sit, 99) }
        }
    }
}
