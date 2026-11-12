import AppKit

// Все коты рисуются кодом. Один и тот же рисунок даёт оба стиля:
// «иллюстрация» — сглаженный рендер в 2x, «пиксель-арт» — тот же рисунок
// в разрешении 1/3 без сглаживания, с контуром, растянутый без интерполяции.

enum ArtStyle: Int { case pixel = 0, illustration = 1 }
enum Eyes { case normal, closed, wide, happy }
enum PoseKind { case side, sit, sitBack, curl, seal, lounge, loaf, face, wall }

struct Pose {
    var kind = PoseKind.sit
    var t: Double = 0
    var eyes = Eyes.normal
    var walk: CGFloat = 0
    var crouch: CGFloat = 0
    var air: CGFloat = 0
    var pawLift: CGFloat = 0
    var stretch: CGFloat = 0
    var scratch: CGFloat = 0
    var headTurn: CGFloat = 0
    var headDip: CGFloat = 0
    var grab: CGFloat = 0
    var snow: CGFloat = 0
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

struct CatLook {
    let name: String
    let fur, furLight, furDark, earIn, eye, line, nose, whisker, pixelOutline: CGColor
    let size, chub, headRX, headRY, earH, leg, tailLen, tailW, bodyLen, eyeRX, eyeRY: CGFloat
    let squint, roundPupil: Bool
    let speed: CGFloat

    static let tom = CatLook(
        name: "Том",
        fur: rgb(0x5f6673), furLight: rgb(0x717988), furDark: rgb(0x484d57), earIn: rgb(0x474c56),
        eye: rgb(0xc9d25c), line: rgb(0x2c2f35), nose: rgb(0x2f3238), whisker: rgb(0xaab0ba),
        pixelOutline: rgb(0x2a2c31),
        size: 1.0, chub: 1.12, headRX: 19, headRY: 15.5, earH: 16, leg: 13, tailLen: 34, tailW: 6.5,
        bodyLen: 27, eyeRX: 0.27, eyeRY: 0.29, squint: true, roundPupil: false, speed: 44)

    static let pirozhok = CatLook(
        name: "Пирожок",
        fur: rgb(0x1c1c20), furLight: rgb(0x2c2c33), furDark: rgb(0x0f0f12), earIn: rgb(0x35323b),
        eye: rgb(0xd4e04e), line: rgb(0x5a5a64), nose: rgb(0x47474f), whisker: rgb(0x60606a),
        pixelOutline: rgb(0x5a5a66),
        size: 0.82, chub: 1.3, headRX: 20, headRY: 17, earH: 12, leg: 9, tailLen: 26, tailW: 6.5,
        bodyLen: 22, eyeRX: 0.3, eyeRY: 0.36, squint: false, roundPupil: true, speed: 52)
}

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

final class Painter {
    let c: CGContext
    let look: CatLook
    let pixel: Bool
    let white = rgb(0xffffff)
    let pupil = rgb(0x101013)

    init(_ c: CGContext, _ look: CatLook, pixel: Bool) { self.c = c; self.look = look; self.pixel = pixel }

    func ell(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ col: CGColor, rot: CGFloat = 0) {
        c.saveGState()
        c.translateBy(x: x, y: y)
        if rot != 0 { c.rotate(by: rot) }
        c.setFillColor(col)
        c.fillEllipse(in: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
        c.restoreGState()
    }

    func poly(_ p: [CGPoint], _ col: CGColor) {
        c.setFillColor(col); c.beginPath(); c.addLines(between: p); c.closePath(); c.fillPath()
    }

    func limb(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat, _ col: CGColor) {
        c.setStrokeColor(col); c.setLineWidth(w); c.setLineCap(.round)
        c.beginPath(); c.move(to: a); c.addLine(to: b); c.strokePath()
    }

    func curve(_ a: CGPoint, _ q: CGPoint, _ b: CGPoint, _ w: CGFloat, _ col: CGColor) {
        c.setStrokeColor(col); c.setLineWidth(w); c.setLineCap(.round)
        c.beginPath(); c.move(to: a); c.addQuadCurve(to: b, control: q); c.strokePath()
    }

    /// Прямоугольник в «арт-пикселях», привязанный к сетке (только для пиксельного стиля).
    func px(_ at: CGPoint, _ w: Int, _ h: Int, _ col: CGColor, dx: Int = 0, dy: Int = 0) {
        let d = at.applying(c.ctm)
        let ox = (d.x - CGFloat(w) / 2).rounded() + CGFloat(dx)
        let oy = (d.y - CGFloat(h) / 2).rounded() + CGFloat(dy)
        c.saveGState()
        c.concatenate(c.ctm.inverted())
        c.setFillColor(col)
        c.fill(CGRect(x: ox, y: oy, width: CGFloat(w), height: CGFloat(h)))
        c.restoreGState()
    }

    // MARK: голова

    func eye(_ p: CGPoint, side s: CGFloat, _ e: Eyes) {
        let L = look
        let erx = L.headRX * L.eyeRX, ery = L.headRY * L.eyeRY
        if pixel {
            switch e {
            case .closed: px(p, 3, 1, L.line)
            case .happy:
                px(p, 1, 1, L.line, dx: -1); px(p, 1, 1, L.line, dx: 1); px(p, 1, 1, L.line, dy: 1)
            case .normal where L.squint:
                px(p, 3, 1, L.eye); px(p, 1, 1, pupil); px(p, 3, 1, L.line, dy: 1)
            case .normal:
                px(p, 3, 3, L.eye); px(p, 1, 1, pupil)
            case .wide:
                if L.squint { px(p, 3, 2, L.eye); px(p, 1, 2, pupil) }
                else { px(p, 3, 3, L.eye); px(p, 1, 3, pupil) }
            }
            return
        }
        c.saveGState()
        c.translateBy(x: p.x, y: p.y)
        switch e {
        case .closed:
            curve(P(-erx, 0.5), P(0, -ery * 0.8), P(erx, 0.5), 1.5, L.line)
        case .happy:
            curve(P(-erx, -1), P(0, ery * 1.2), P(erx, -1), 1.6, L.line)
        default:
            let wide = e == .wide
            let r = CGRect(x: -erx, y: -ery, width: 2 * erx, height: 2 * ery)
            let lidY = ery * 0.12
            c.saveGState()
            c.addEllipse(in: r); c.clip()
            c.setFillColor(L.eye); c.fill(r)
            let pw = L.roundPupil ? erx * (wide ? 0.84 : 0.6) : erx * (wide ? 0.55 : 0.24)
            let ph = L.roundPupil ? ery * (wide ? 0.88 : 0.72) : ery * 0.92
            ell(0, 0, pw, ph, pupil)
            ell(erx * 0.32, ery * 0.36, erx * 0.17, erx * 0.17, rgb(0xffffff, 0.9))
            if L.squint && !wide {
                poly([P(-erx - 1, lidY - s * 1.2), P(erx + 1, lidY + s * 1.2), P(erx + 1, ery + 2), P(-erx - 1, ery + 2)], L.fur)
            }
            c.restoreGState()
            if L.squint && !wide {
                limb(P(-erx, lidY - s * 1.2), P(erx, lidY + s * 1.2), 1.6, L.line)
            }
        }
        c.restoreGState()
    }

    func head(_ at: CGPoint, eyes: Eyes, shift: CGFloat = 0, back: Bool = false,
              scale: CGFloat = 1, rot: CGFloat = 0, snow: CGFloat = 0) {
        let L = look, rx = L.headRX, ry = L.headRY
        c.saveGState()
        c.translateBy(x: at.x, y: at.y)
        if rot != 0 { c.rotate(by: rot) }
        if scale != 1 { c.scaleBy(x: scale, y: scale) }
        for s: CGFloat in [-1, 1] {
            let a = P(s * rx * 0.92, ry * 0.3), tip = P(s * rx * 0.8, ry * 0.55 + L.earH), b = P(s * rx * 0.1, ry * 0.9)
            poly([a, tip, b], L.fur)
            if !back {
                let m = P((a.x + tip.x + b.x) / 3, (a.y + tip.y + b.y) / 3)
                let inner = [a, tip, b].map { P(m.x + ($0.x - m.x) * 0.55, m.y + ($0.y - m.y) * 0.55) }
                poly(inner, L.earIn)
            }
        }
        ell(0, 0, rx, ry, L.fur)
        ell(0, -ry * 0.28, rx * 1.08, ry * 0.7, L.fur)
        if snow > 0.05 {
            ell(0, ry * 0.95, rx * 0.5 * min(1, snow + 0.3), 2 + 2.5 * snow, white)
        }
        if back { c.restoreGState(); return }
        let ex = rx * 0.43, ey = ry * 0.04
        eye(P(-ex + shift, ey), side: -1, eyes)
        eye(P(ex + shift, ey), side: 1, eyes)
        let ny = -ry * 0.3
        if pixel {
            px(P(shift, -ry * 0.4), 2, 1, L.nose)
        } else {
            poly([P(shift - 2.7, ny), P(shift + 2.7, ny), P(shift, ny - 3.3)], L.nose)
            curve(P(shift, ny - 3.3), P(shift - 2.5, ny - 7.2), P(shift - 5.6, ny - 5.4), 1.1, L.line)
            curve(P(shift, ny - 3.3), P(shift + 2.5, ny - 7.2), P(shift + 5.6, ny - 5.4), 1.1, L.line)
            for s: CGFloat in [-1, 1] {
                limb(P(shift + s * rx * 0.55, ny - 2), P(shift + s * rx * 1.28, ny + 0.5), 0.7, L.whisker)
                limb(P(shift + s * rx * 0.55, ny - 4), P(shift + s * rx * 1.25, ny - 5.5), 0.7, L.whisker)
            }
        }
        c.restoreGState()
    }

    // MARK: позы

    func draw(_ p: Pose) {
        switch p.kind {
        case .side: side(p)
        case .sit: sit(p, back: false)
        case .sitBack: sit(p, back: true)
        case .curl: curl(p)
        case .seal: seal(p)
        case .lounge: lounge(p)
        case .loaf: loaf(p)
        case .face: face(p)
        case .wall: wall(p)
        }
    }

    private func paw(_ at: CGPoint, _ col: CGColor) { ell(at.x + 1, at.y, 4.6, 3.3, col) }

    func side(_ p: Pose) {
        let L = look, t = CGFloat(p.t)
        let leg = L.leg * (1 - 0.55 * p.crouch)
        let ry = 13.5 * L.chub, rx = L.bodyLen
        let by = leg + ry - 3
        let ph = t * 9
        let hipF = rx * 0.55, hipR = -rx * 0.6, hipY = by - ry * 0.35
        func foot(_ hip: CGFloat, _ off: CGFloat, front: Bool) -> CGPoint {
            var fx = hip + p.walk * 5 * sin(ph + off)
            var fy = 3.2 + p.walk * max(0, cos(ph + off)) * 3
            if front { fx += p.air * 11 + p.stretch * 12 + p.scratch * 4.5 * sin(t * 13 + off); fy += p.air * 5 } else { fx -= p.air * 11; fy += p.air * 2 }
            return P(fx, fy)
        }
        let tb = P(-rx + 3, by + 2)
        if p.crouch > 0.5 {
            curve(tb, P(-rx - 12, by - 2), P(-rx - L.tailLen * 0.75, by + 3 * sin(t * 14)), L.tailW, L.fur)
        } else if p.air > 0.5 {
            curve(tb, P(-rx - 14, by + 6), P(-rx - L.tailLen * 0.8, by + 10), L.tailW, L.fur)
        } else {
            curve(tb, P(-rx - 13, by + 5), P(-rx - 7 + 3 * sin(t * 2.5), by + L.tailLen * 0.72), L.tailW, L.fur)
        }
        let ff = foot(hipF + 3, .pi, front: true), fr = foot(hipR + 3, 0, front: false)
        limb(P(hipF + 3, hipY), ff, 6.5, L.furDark); paw(ff, L.furDark)
        limb(P(hipR + 3, hipY), fr, 6.5, L.furDark); paw(fr, L.furDark)
        let wig = p.crouch > 0.5 ? sin(t * 16) * 1.3 : 0
        ell(-1, by, rx, ry, L.fur, rot: -0.22 * p.stretch)
        ell(-rx * 0.45, by + 1 + wig + p.stretch * 4, rx * 0.6, ry * 0.97, L.fur)
        if p.snow > 0.05 { ell(-2, by + ry - 1, rx * 0.6 * p.snow, 2.5 + 2 * p.snow, white) }
        var nf = foot(hipF, 0, front: true)
        if p.pawLift > 0 { nf = P(hipF + 8, 9 + sin(t * 38) * 2.2) }
        let nr = foot(hipR, .pi, front: false)
        limb(P(hipF, hipY - p.stretch * 5), nf, 7, L.furLight); paw(nf, L.furLight)
        limb(P(hipR, hipY), nr, 7, L.furLight); paw(nr, L.furLight)
        head(P(rx * 0.72 + 3, by + ry * 0.5 + 2 - p.crouch * 3 - p.stretch * 9), eyes: p.eyes, shift: 2.5)
    }

    /// Точит когти о стену: стоит на задних лапах боком к нам, стена — в Art.wallReach впереди.
    func wall(_ p: Pose) {
        let L = look, t = CGFloat(p.t)
        let wx = Art.wallReach - 3.5
        let hy = 8 + L.bodyLen * 1.6, ph = t * 11
        func arm(_ from: CGPoint, _ off: CGFloat, _ w: CGFloat, _ col: CGColor) {
            let tip = P(wx, hy + 9 + 6 * sin(ph + off))
            limb(from, tip, w, col); ell(tip.x, tip.y + 1, 3.4, 4.8, col)
        }
        curve(P(-13, 6), P(-24, 1), P(-14 - L.tailLen * 0.7, 5 + 3 * sin(t * 3)), L.tailW, L.fur)
        arm(P(13, hy - 13), 0, 6.5, L.furDark)
        limb(P(1, 9), P(6, 3.2), 6.5, L.furDark); paw(P(6, 3.2), L.furDark)
        ell(-5, 12, 13.5, 12.5, L.fur)
        ell(1, 4 + L.bodyLen * 0.9, 12.5 * L.chub, L.bodyLen * 0.9, L.fur, rot: -0.32)
        limb(P(-9, 9), P(-4, 3.2), 7, L.furLight); paw(P(-4, 3.2), L.furLight)
        head(P(-3, hy), eyes: p.eyes, shift: 4, rot: 0.15)
        arm(P(11, hy - 16), .pi, 7, L.furLight)
    }

    func sit(_ p: Pose, back: Bool) {
        let L = look, t = CGFloat(p.t)
        let wag = sin(t * 2.2)
        let bw = 20 * L.chub, bh: CGFloat = 19
        if back {
            curve(P(6, 5), P(13, -5), P(9 + 5 * wag, -15), L.tailW, L.fur)
        } else {
            curve(P(12, 5), P(18 + L.tailLen * 0.7, -1), P(15 + L.tailLen * 0.72, 10 + 6 * wag), L.tailW, L.fur)
        }
        ell(0, bh - 1, bw, bh, L.fur)
        if back {
            ell(-bw * 0.55, 7, 9, 8, L.fur); ell(bw * 0.55, 7, 9, 8, L.fur)
        } else {
            ell(0, 15, 9, 12, L.furLight)
            ell(-8, 3.6, 6.5, 4, L.furLight)
            if p.pawLift <= 0 {
                ell(8, 3.6, 6.5, 4, L.furLight)
            } else {
                let tip = P(19 + 3 * p.pawLift, 30 + 16 * p.pawLift)
                limb(P(11, 20), tip, 6.5, L.furLight); paw(tip, L.furLight)
            }
        }
        let hy = bh * 2 - 8 + L.headRY - p.headDip * 6
        head(P(back ? 5 * p.headTurn : 0, hy), eyes: p.eyes, shift: back ? 6 * p.headTurn : 0,
             back: back && p.headTurn < 0.5, snow: p.snow)
    }

    func curl(_ p: Pose) {
        let L = look, t = CGFloat(p.t)
        let br = 1 + 0.035 * sin(t * 1.6)
        let rx = L.bodyLen, ry = 13 * L.chub * br
        ell(0, ry - 1, rx, ry, L.fur)
        head(P(-rx * 0.5, 11), eyes: .closed, scale: 0.8, rot: 0.22)
        curve(P(rx - 4, 7), P(rx * 0.4, -3), P(-3, 4), L.tailW, L.furLight)
        if p.snow > 0.05 {
            let s = p.snow
            ell(2, 2 * ry - 3, rx * 0.72 * min(1, s + 0.25), 2.5 + 3.5 * s, white)
            ell(-rx * 0.5, 11 + 13 * 0.8, 7 * s, 2 + 2 * s, white)
        }
    }

    func seal(_ p: Pose) {
        let L = look, t = CGFloat(p.t)
        let rx = L.bodyLen, ry = 12.5 * L.chub
        let w = sin(t * 3)
        curve(P(-rx + 2, 6), P(-rx - 10, 3), P(-rx - L.tailLen * 0.6, 5 + 3 * sin(t * 5)), L.tailW, L.fur)
        ell(-2, ry, rx, ry, L.fur)
        ell(-2, ry + 4, rx * 0.68, ry * 0.58, L.furLight)
        let top = ry * 1.55, len = L.leg + 4
        let r1 = P(-rx * 0.68 + 2 * w, top + len), r2 = P(-rx * 0.3 - 2 * w, top + len + 2)
        limb(P(-rx * 0.6, top), r1, 6.5, L.fur); paw(r1, L.furLight)
        limb(P(-rx * 0.28, top + 1), r2, 6.5, L.fur); paw(r2, L.furLight)
        let g = p.grab
        let mid = P(rx * 0.42, top + len + 1)
        var f1 = P(rx * 0.25 - 2 * w, top + len + 1), f2 = P(rx * 0.62 + 2 * w, top + len - 1)
        f1 = P(f1.x + (mid.x - 3 - f1.x) * g, f1.y + (mid.y - f1.y) * g)
        f2 = P(f2.x + (mid.x + 3 - f2.x) * g, f2.y + (mid.y - f2.y) * g)
        limb(P(rx * 0.28, top + 1), f1, 6.5, L.fur); paw(f1, L.furLight)
        limb(P(rx * 0.58, top), f2, 6.5, L.fur); paw(f2, L.furLight)
        head(P(rx * 0.85 + 4, 17), eyes: p.eyes, rot: -1.95)
    }

    func lounge(_ p: Pose) {
        let L = look, t = CGFloat(p.t)
        let rx = L.bodyLen
        curve(P(-rx - 2, 9), P(-rx - 10, 0), P(-rx - 6 + 3 * sin(t * 1.5), -14), L.tailW, L.fur)
        ell(-rx * 0.7, 12, 12, 12 * L.chub, L.fur)
        ell(-3, 11, rx + 3, 11 * L.chub, L.fur)
        let tip = P(rx * 0.5 + 2 * sin(t * 1.2), -11)
        limb(P(rx * 0.45, 6), tip, 6.5, L.furLight); paw(tip, L.furLight)
        ell(rx * 0.95, 3.6, 7, 3.6, L.furLight)
        head(P(rx * 0.7, 21), eyes: p.eyes)
    }

    func loaf(_ p: Pose) {
        let L = look
        let rx = L.bodyLen
        ell(0, 13.5, rx, 14 * L.chub, L.fur)
        ell(rx * 0.45, 5, 9, 4.5, L.furLight)
        curve(P(-rx + 3, 6), P(-rx * 0.5, -2), P(0, 3.5), L.tailW, L.furLight)
        head(P(rx * 0.45, 25), eyes: p.eyes)
    }

    func face(_ p: Pose) {
        let L = look
        ell(0, -4, 30, 22, L.fur)
        head(P(0, 30), eyes: p.eyes, scale: 1.45)
    }
}

enum Art {
    static let canvas = CGSize(width: 126, height: 99)
    static let ground: CGFloat = 18
    /// расстояние от кота до стены, о которую он точит когти (до масштаба кота)
    static let wallReach: CGFloat = 32

    static func render(_ look: CatLook, _ style: ArtStyle, _ pose: Pose) -> CGImage {
        let pixel = style == .pixel
        let k: CGFloat = pixel ? 1.0 / 3 : (pose.kind == .face ? 6 : 2)
        let w = Int(canvas.width * k), h = Int(canvas.height * k)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info)!
        ctx.setShouldAntialias(!pixel)
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: canvas.width / 2, y: ground)
        ctx.scaleBy(x: look.size, y: look.size)
        Painter(ctx, look, pixel: pixel).draw(pose)
        if pixel {
            outline(ctx, w, h, look.pixelOutline)
            return ctx.makeImage()!
        }
        let img = ctx.makeImage()!
        let c2 = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info)!
        c2.setShadow(offset: .zero, blur: k * 1.5, color: rgb(0xffffff, 0.6))
        c2.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c2.makeImage()!
    }

    static func outline(_ ctx: CGContext, _ w: Int, _ h: Int, _ col: CGColor) {
        guard let data = ctx.data else { return }
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var solid = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) { solid[i] = p[i * 4 + 3] > 0 }
        let comp = col.components ?? [0, 0, 0, 1]
        let r = UInt8(comp[0] * 255), g = UInt8(comp[1] * 255), b = UInt8(comp[2] * 255)
        for y in 0..<h {
            for x in 0..<w where !solid[y * w + x] {
                let near = (x > 0 && solid[y * w + x - 1]) || (x < w - 1 && solid[y * w + x + 1])
                    || (y > 0 && solid[(y - 1) * w + x]) || (y < h - 1 && solid[(y + 1) * w + x])
                if near {
                    let i = (y * w + x) * 4
                    p[i] = r; p[i + 1] = g; p[i + 2] = b; p[i + 3] = 255
                }
            }
        }
    }

    static func writePNG(_ img: CGImage, _ path: String) {
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Контактный лист со всеми позами — для проверки рисунков.
    static func sheet(_ path: String) {
        var poses: [(String, Pose)] = []
        func add(_ n: String, _ f: (inout Pose) -> Void) { var p = Pose(); p.t = 0.4; f(&p); poses.append((n, p)) }
        add("walk") { $0.kind = .side; $0.walk = 1 }
        add("crouch") { $0.kind = .side; $0.crouch = 1; $0.eyes = .wide }
        add("jump") { $0.kind = .side; $0.air = 1; $0.eyes = .wide }
        add("shake") { $0.kind = .side; $0.pawLift = 1 }
        add("stretch") { $0.kind = .side; $0.stretch = 1; $0.eyes = .closed }
        add("scratch") { $0.kind = .side; $0.stretch = 0.8; $0.scratch = 1; $0.eyes = .closed }
        add("wall") { $0.kind = .wall }
        add("sit") { $0.kind = .sit; $0.snow = 0.8 }
        add("swat") { $0.kind = .sit; $0.pawLift = 1; $0.eyes = .wide }
        add("happy") { $0.kind = .sit; $0.eyes = .happy }
        add("back") { $0.kind = .sitBack }
        add("turn") { $0.kind = .sitBack; $0.headTurn = 1 }
        add("curl") { $0.kind = .curl; $0.snow = 0.8 }
        add("seal") { $0.kind = .seal; $0.eyes = .wide }
        add("grab") { $0.kind = .seal; $0.grab = 1; $0.eyes = .happy }
        add("lounge") { $0.kind = .lounge }
        add("loaf") { $0.kind = .loaf }
        add("face") { $0.kind = .face }
        let cols = 8, cw = 252, ch = 198
        let combos: [(CatLook, ArtStyle)] = [(.tom, .illustration), (.tom, .pixel), (.pirozhok, .illustration), (.pirozhok, .pixel)]
        let rowsPer = (poses.count + cols - 1) / cols
        let W = cols * cw, H = combos.count * rowsPer * ch
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        for (ci, combo) in combos.enumerated() {
            ctx.setFillColor(ci % 2 == 0 ? rgb(0x8fa3b8) : rgb(0x3b4654))
            ctx.fill(CGRect(x: 0, y: H - (ci + 1) * rowsPer * ch, width: W, height: rowsPer * ch))
            for (pi, pose) in poses.enumerated() {
                let img = render(combo.0, combo.1, pose.1)
                let x = (pi % cols) * cw, y = H - (ci * rowsPer + pi / cols + 1) * ch
                ctx.draw(img, in: CGRect(x: x, y: y, width: cw, height: ch))
                ctx.setFillColor(rgb(0xffffff, 0.5))
                ctx.fill(CGRect(x: x, y: y + 36, width: cw, height: 1))
            }
        }
        writePNG(ctx.makeImage()!, path)
    }
}
