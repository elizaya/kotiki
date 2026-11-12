import AppKit
import SpriteKit

final class ClickView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class MenuAction: NSObject {
    let f: () -> Void
    init(_ f: @escaping () -> Void) { self.f = f }
    @objc func fire() { f() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var panel: OverlayPanel!
    var view: ClickView!
    var scene: OverlayScene!
    var status: NSStatusItem!
    var actions: [MenuAction] = []
    var paused = false
    var hiddenUntil: Date?

    func applicationDidFinishLaunching(_ note: Notification) {
        let frame = NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel = OverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        view = ClickView(frame: NSRect(origin: .zero, size: frame.size))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 30
        view.ignoresSiblingOrder = true
        scene = OverlayScene(size: frame.size)
        scene.scaleMode = .resizeFill
        scene.host = panel
        panel.contentView = view
        view.presentScene(scene)
        panel.orderFrontRegardless()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = Self.icon()
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let f = NSScreen.screens.first?.frame else { return }
            self.panel.setFrame(f, display: true)
        }
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, let h = self.hiddenUntil, Date() > h else { return }
            self.hiddenUntil = nil; self.refreshVisibility()
        }

        // отладка: KOTIKI_DEMO=seal KOTIKI_SNAPSHOT=/path.png
        let env = ProcessInfo.processInfo.environment
        if env["KOTIKI_SNAPSHOT"] == nil { Updater.shared.start() }
        if env["KOTIKI_DOCK"] != nil { scene.forceDock = true }
        // отладка: KOTIKI_EDITOR=/path.png открывает окно «Мой кот» и сохраняет его снимок
        if let path = env["KOTIKI_EDITOR"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.editCat(Prefs.specs.first?.id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let v = CatEditor.shared.window?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                v.wantsLayer = true; v.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; v.display()
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                if env["KOTIKI_SNAPSHOT"] == nil { NSApp.terminate(nil) }
            }
        }
        if let d = env["KOTIKI_DEMO"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.scene.demo(d) }
        }
        if let path = env["KOTIKI_SNAPSHOT"] {
            let delay = Double(env["KOTIKI_DELAY"] ?? "") ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let sim = Double(env["KOTIKI_SIM"] ?? "") {
                    self.view.isPaused = true; self.scene.last = 0
                    self.scene.sim = true
                    var t = 100.0
                    let demoAt = Double(env["KOTIKI_DEMO_AT"] ?? "") ?? sim - 4
                    var fired = false
                    while t < 100 + sim {
                        if !fired, t - 100 > demoAt, let d = env["KOTIKI_DEMO"] { fired = true; self.scene.demo(d) }
                        self.scene.update(t); t += 1.0 / 30
                    }
                }
                if let img = self.view.texture(from: self.scene)?.cgImage() {
                    let c = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    c.setFillColor(rgb(0x6f8196)); c.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
                    c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
                    Art.writePNG(c.makeImage()!, path)
                }
                print(self.scene.surfaces.map { "\($0.id) y=\(Int($0.y)) \($0.segs.map { "\(Int($0.lowerBound))-\(Int($0.upperBound))" })" }.joined(separator: "\n"))
                for (id, p) in self.scene.piles { print("pile", id, "max", p.h.max() ?? 0, "avg", p.h.reduce(0, +) / Float(max(1, p.h.count)), "flakes", self.scene.flakes.count, "snow", Prefs.snow, "style", Prefs.style) }
                print("overlapT", self.scene.overlapT, "wallTrips", self.scene.scratches, "dockUp", self.scene.dockUp)
                print("meets", self.scene.meets, "meet", self.scene.meet.map { "\($0.kind) phase \($0.phase)" } ?? "-", "yawns", self.scene.yawns)
                print("selfPlays", self.scene.selfPlays, "bats", self.scene.bats, "knocks", self.scene.knocks, "snowmen", self.scene.snowmen.map { $0.radii.count })
                print("clock", self.scene.clock, "visible", self.panel.isVisible, "occl", self.panel.occlusionState.contains(.visible), "paused", self.view.isPaused, self.scene.isPaused, "frame", self.panel.frame)
                print(self.scene.cats.map { "\($0.look.name) \($0.state) x=\(Int($0.x)) y=\(Int($0.y)) surf=\($0.surf)" })
                NSApp.terminate(nil)
            }
        }
    }

    static func icon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let p = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 14, height: 11))
            p.move(to: NSPoint(x: 2.5, y: 9)); p.line(to: NSPoint(x: 3, y: 17)); p.line(to: NSPoint(x: 8, y: 12.5)); p.close()
            p.move(to: NSPoint(x: 15.5, y: 9)); p.line(to: NSPoint(x: 15, y: 17)); p.line(to: NSPoint(x: 10, y: 12.5)); p.close()
            p.fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 5, y: 6.5, width: 2.6, height: 2.2)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.4, y: 6.5, width: 2.6, height: 2.2)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    func refreshVisibility() {
        let hidden = paused || hiddenUntil != nil
        view.isPaused = hidden
        if hidden { panel.ignoresMouseEvents = true; panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// id — какого кота настраивать; nil — завести нового
    func editCat(_ id: String?) {
        CatEditor.shared.onChange = { [weak self] in self?.scene.applyCats() }
        CatEditor.shared.show(id)
    }

    func showHelp() {
        let k = ["⌥ (Option)", "⇧ (Shift)", "⌘ (Command)"][max(0, min(2, Prefs.playKey))]
        let a = NSAlert()
        a.messageText = "Как играть со снегом"
        a.informativeText = """
        Стряхнуть снег
        Быстро проведите курсором по сугробу. Клавиши не нужны.

        Слепить снежок
        Зажмите \(k) и, не отпуская её, нажмите кнопку мыши на сугробе. Водите мышью по снегу — ком растёт.

        Бросить снежок
        Отпустите кнопку мыши на ходу — полетит туда, куда вели.

        Поставить ком
        Остановите мышь и отпустите кнопку — ком останется стоять.

        Снеговик
        Поставьте на ком второй, поменьше, и сверху третий.

        Разобрать снеговика
        \(k) + нажатие на снеговика снимает верхний ком.

        Коты
        Клик — погладить. Подержать курсор — почесать. Зажать и тянуть — перенести.
        """
        a.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: меню

    func item(_ title: String, on: Bool = false, _ f: @escaping () -> Void) -> NSMenuItem {
        let a = MenuAction { [weak self] in f(); self?.scene.applyPrefs() }
        actions.append(a)
        let i = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        i.target = a
        i.state = on ? .on : .off
        return i
    }

    func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let m = NSMenu()
        items.forEach { m.addItem($0) }
        i.submenu = m
        return i
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        actions.removeAll()
        menu.addItem(item(paused ? "Продолжить" : "Пауза") { self.paused.toggle(); self.refreshVisibility() })
        if hiddenUntil != nil {
            menu.addItem(item("Вернуть котов") { self.hiddenUntil = nil; self.refreshVisibility() })
        } else {
            menu.addItem(item("Спрятать на час") { self.hiddenUntil = Date().addingTimeInterval(3600); self.refreshVisibility() })
        }
        menu.addItem(.separator())
        var catItems = [
            item("Том", on: Prefs.tom) { Prefs.tom.toggle() },
            item("Пирожок", on: Prefs.pirozhok) { Prefs.pirozhok.toggle() }]
        let own = Prefs.specs
        for s in own {
            catItems.append(item(s.look.name, on: s.on) {
                var all = Prefs.specs
                if let i = all.firstIndex(where: { $0.id == s.id }) { all[i].on.toggle(); Prefs.specs = all }
            })
        }
        catItems.append(.separator())
        for s in own { catItems.append(item("Настроить: \(s.look.name)…") { self.editCat(s.id) }) }
        if own.count < Prefs.maxSpecs {
            catItems.append(item(own.isEmpty ? "Создать своего кота…" : "Добавить ещё кота…") { self.editCat(nil) })
        }
        menu.addItem(sub("Коты", catItems))
        menu.addItem(sub("Стиль", [
            item("Иллюстрация", on: Prefs.style == 1) { Prefs.style = 1 },
            item("Пиксель-арт", on: Prefs.style == 0) { Prefs.style = 0 }]))
        let snowNames = ["Выключен", "Лёгкий", "Обычный", "Метель"]
        var snow = snowNames.enumerated().map { i, n in item(n, on: Prefs.snow == i) { Prefs.snow = i } }
        snow.append(.separator())
        snow.append(item("Стряхнуть сугробы") { self.scene.clearSnow() })
        menu.addItem(sub("Снег", snow))
        let winds = [(-2, "Сильный влево"), (-1, "Влево"), (0, "Штиль"), (1, "Вправо"), (2, "Сильный вправо")]
        menu.addItem(sub("Ветер", winds.map { v, n in item(n, on: Prefs.wind == v) { Prefs.wind = v } }))
        menu.addItem(sub("Выходки", ["Редко", "Иногда", "Часто"].enumerated().map { i, n in item(n, on: Prefs.antics == i) { Prefs.antics = i } }))
        let keys = ["⌥ Option", "⇧ Shift", "⌘ Command"]
        let hint = NSMenuItem(title: "Клавиша для снежков (держать и нажимать мышкой):", action: nil, keyEquivalent: "")
        var play = [item("Включена", on: Prefs.play) { Prefs.play.toggle() }, item("Как играть…") { self.showHelp() }, .separator(), hint]
        play += keys.enumerated().map { i, n in item(n, on: Prefs.playKey == i) { Prefs.playKey = i } }
        play.append(.separator())
        play.append(item("Коты ломают снеговиков", on: Prefs.tomBreaks) { Prefs.tomBreaks.toggle() })
        menu.addItem(sub("Игра со снегом", play))
        menu.addItem(item("Ловушка для курсора", on: Prefs.trap) { Prefs.trap.toggle() })
        menu.addItem(item("Осуждающий взгляд по ночам", on: Prefs.judge) { Prefs.judge.toggle() })
        menu.addItem(.separator())
        let demos = [("seal", "Тюлень"), ("window", "Смотрит на снег"), ("lounge", "Барин"), ("loaf", "«Это моё окно»"),
                     ("hunt", "Охота на курсор"), ("sleep", "Сон"), ("yawn", "Зевает"), ("sneeze", "Чих"), ("swat", "Ловит снежинку"),
                     ("shake", "Трясёт лапой"), ("scratch", "Точит когти об пол"), ("wall", "Точит когти об стену"), ("snowman", "Снеговик (для проверки)"), ("judge", "Осуждающий взгляд")]
        var demoItems = demos.map { k, n in item(n) { self.scene.demo(k) } }
        if scene.cats.count > 1 {
            // сценки на двоих
            demoItems.append(.separator())
            let pairs = [("greet", "Здороваются"), ("together", "Сидят рядом"), ("nap", "Спят вместе"), ("chase", "Догонялки")]
            demoItems += pairs.map { k, n in item(n) { self.scene.demo(k) } }
        }
        menu.addItem(sub("Показать сценку", demoItems))
        menu.addItem(.separator())
        let up = Updater.shared
        if let s = up.staged {
            menu.addItem(item("Обновить до \(s.version) и перезапустить") { up.install() })
        } else if let m = up.manual {
            menu.addItem(item("Доступна версия \(m.version)…") { NSWorkspace.shared.open(m.page) })
        }
        let state = [Updater.Status.checking: " — проверяю…", .upToDate: " — последняя", .failed: " — не удалось проверить"][up.status] ?? ""
        menu.addItem(sub("Обновления", [
            NSMenuItem(title: "Версия \(up.current)\(state)", action: nil, keyEquivalent: ""),
            item("Обновлять автоматически", on: Prefs.autoUpdate) { Prefs.autoUpdate.toggle() },
            item("Проверить сейчас") { up.check() }]))
        menu.addItem(item("Выйти") { NSApp.terminate(nil) })
    }
}

let args = CommandLine.arguments
if args.count > 2, args[1] == "--sheet" {
    Art.sheet(args[2], custom: args.count > 3)
} else if args.count > 2, args[1] == "--icon" {
    var p = Pose(); p.kind = .face
    Art.writePNG(Art.render(.tom, .illustration, p), args[2])
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
