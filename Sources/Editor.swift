import AppKit

// Окно «Мой кот»: внешность, характер и набор сценок своего кота.
// Всё применяется сразу: кот на экране и превью меняются на ходу.

final class ControlAction: NSObject {
    let f: (NSControl) -> Void
    init(_ f: @escaping (NSControl) -> Void) { self.f = f }
    @objc func fire(_ sender: NSControl) { f(sender) }
}

final class CatEditor: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    static let shared = CatEditor()

    var window: NSWindow?
    var spec = CatSpec()
    /// зовётся после каждого изменения
    var onChange: () -> Void = {}
    var actions: [ControlAction] = []
    let preview = NSView()
    var timer: Timer?
    var clock = 0.0
    var poseIx = 0

    /// id — какого кота настраивать; nil — завести нового
    func show(_ id: String?) {
        var all = Prefs.specs
        if let s = all.first(where: { $0.id == id }) { spec = s } else {
            // новый кот: случайный, чтобы отличался от остальных, и сразу на экран
            guard all.count < Prefs.maxSpecs else { return }
            spec = all.isEmpty ? CatSpec() : CatSpec.random()
            let names = ["Рыжик", "Мурзик", "Барсик", "Пушок", "Кекс", "Плюша"]
            spec.name = names.first { n in !all.contains { $0.name == n } } ?? "Кот"
            all.append(spec); Prefs.specs = all
            onChange()
        }
        window?.close()
        build()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in self?.tick() }
    }

    func windowWillClose(_ note: Notification) {
        timer?.invalidate(); timer = nil
        NSColorPanel.shared.close()
    }

    func changed() {
        var all = Prefs.specs
        if let i = all.firstIndex(where: { $0.id == spec.id }) { all[i] = spec } else { all.append(spec) }
        Prefs.specs = all
        onChange()
    }

    // MARK: превью

    func tick() {
        clock += 1.0 / 12
        var p = Pose()
        p.t = clock
        switch poseIx {
        case 1: p.kind = .side; p.walk = 1
        case 2: p.kind = .seal; p.eyes = .wide
        case 3: p.kind = .curl
        case 4:
            p.kind = .sit
            let v = clock.truncatingRemainder(dividingBy: 3.2) / 1.9
            if v < 1 { p.yawn = CGFloat(v < 0.3 ? v / 0.3 : (v < 0.7 ? 1 : (1 - v) / 0.3)) }
        default:
            p.kind = .sit
            if clock.truncatingRemainder(dividingBy: 4.3) < 0.16 { p.eyes = .closed }
        }
        let style = ArtStyle(rawValue: Prefs.style) ?? .illustration
        preview.layer?.contents = Art.render(spec.look, style, p, scale: 5)
        preview.layer?.magnificationFilter = style == .pixel ? .nearest : .linear
    }

    // MARK: окно

    func act(_ f: @escaping (NSControl) -> Void) -> ControlAction {
        let a = ControlAction(f); actions.append(a); return a
    }

    func label(_ s: String, small: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        if small { l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor }
        return l
    }

    func header(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 13)
        return l
    }

    func segments(_ names: [String], _ selected: Int, _ f: @escaping (Int) -> Void) -> NSSegmentedControl {
        let a = act { f(($0 as! NSSegmentedControl).selectedSegment) }
        let s = NSSegmentedControl(labels: names, trackingMode: .selectOne, target: a, action: #selector(ControlAction.fire(_:)))
        s.selectedSegment = selected
        return s
    }

    func slider(_ lo: Double, _ hi: Double, _ value: Double, left: String? = nil, right: String? = nil, _ f: @escaping (Double) -> Void) -> NSView {
        let a = act { f($0.doubleValue) }
        let s = NSSlider(value: value, minValue: lo, maxValue: hi, target: a, action: #selector(ControlAction.fire(_:)))
        s.isContinuous = true
        s.widthAnchor.constraint(equalToConstant: left == nil ? 220 : 150).isActive = true
        guard let l = left, let r = right else { return s }
        let row = NSStackView(views: [label(l, small: true), s, label(r, small: true)])
        row.spacing = 6
        return row
    }

    /// Готовые цвета в выпадающем списке и рядом — свой цвет.
    func colorRow(_ presets: [(String, UInt32)], _ value: UInt32, _ f: @escaping (UInt32) -> Void) -> NSView {
        let well = NSColorWell()
        well.color = Self.color(value)
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let pop = NSPopUpButton()
        pop.addItems(withTitles: presets.map { $0.0 } + ["Свой цвет"])
        pop.selectItem(at: presets.firstIndex { $0.1 == value } ?? presets.count)
        let pa = act { [weak well] c in
            let i = (c as! NSPopUpButton).indexOfSelectedItem
            guard i < presets.count else { return }
            well?.color = Self.color(presets[i].1)
            f(presets[i].1)
        }
        pop.target = pa; pop.action = #selector(ControlAction.fire(_:))
        let wa = act { [weak pop] c in
            let hex = Self.hex((c as! NSColorWell).color)
            pop?.selectItem(at: presets.firstIndex { $0.1 == hex } ?? presets.count)
            f(hex)
        }
        well.target = wa; well.action = #selector(ControlAction.fire(_:))
        let row = NSStackView(views: [pop, well])
        row.spacing = 8
        return row
    }

    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    static func hex(_ c: NSColor) -> UInt32 {
        guard let s = c.usingColorSpace(.sRGB) else { return 0x808080 }
        func b(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return b(s.redComponent) << 16 | b(s.greenComponent) << 8 | b(s.blueComponent)
    }

    func build() {
        actions.removeAll()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Мой кот"
        w.isReleasedWhenClosed = false
        w.delegate = self
        window = w

        // слева — превью
        preview.wantsLayer = true
        preview.layer?.backgroundColor = rgb(0x8fa3b8)
        preview.layer?.cornerRadius = 12
        preview.layer?.contentsGravity = .resizeAspect
        preview.widthAnchor.constraint(equalToConstant: 300).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 236).isActive = true
        let poses = segments(["Сидит", "Идёт", "Тюлень", "Спит", "Зевает"], poseIx) { [weak self] i in self?.poseIx = i }
        poses.segmentStyle = .rounded
        poses.controlSize = .small

        let name = NSTextField(string: spec.name)
        name.placeholderString = "Имя кота"
        name.delegate = self
        name.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let showA = act { [weak self] c in self?.spec.on = (c as! NSButton).state == .on; self?.changed() }
        let show = NSButton(checkboxWithTitle: "Выпустить на экран", target: showA, action: #selector(ControlAction.fire(_:)))
        show.state = spec.on ? .on : .off

        let randA = act { [weak self] _ in
            guard let self else { return }
            var s = CatSpec.random(); s.id = self.spec.id; s.on = self.spec.on; s.name = self.spec.name; s.tricks = self.spec.tricks
            self.spec = s; self.changed(); self.rebuild()
        }
        let rand = NSButton(title: "Случайный кот", target: randA, action: #selector(ControlAction.fire(_:)))

        let delA = act { [weak self] _ in self?.remove() }
        let del = NSButton(title: "Удалить кота…", target: delA, action: #selector(ControlAction.fire(_:)))

        let left = NSStackView(views: [preview, poses, label("Имя", small: true), name, show, rand, del])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 10
        left.setCustomSpacing(18, after: poses)
        left.setCustomSpacing(4, after: left.views[2])
        left.setCustomSpacing(18, after: name)

        // справа — настройки
        let set: (WritableKeyPath<CatSpec, Double>) -> (Double) -> Void = { [weak self] k in { v in self?.spec[keyPath: k] = v; self?.changed() } }
        let grid = NSGridView(views: [
            [header("Внешность"), NSGridCell.emptyContentView],
            [label("Шерсть"), colorRow(CatSpec.furs, spec.fur) { [weak self] v in self?.spec.fur = v; self?.changed() }],
            [label("Узор"), segments(["Однотонный", "В носочках", "Полосатый"], spec.pattern) { [weak self] i in self?.spec.pattern = i; self?.changed() }],
            [label("Пушистость"), segments(["Гладкий", "Пушистый", "Очень пушистый"], spec.fluff) { [weak self] i in self?.spec.fluff = i; self?.changed() }],
            [label("Глаза"), colorRow(CatSpec.eyes, spec.eye) { [weak self] v in self?.spec.eye = v; self?.changed() }],
            [label("Зрачок"), segments(["Щёлка", "Круглый"], spec.roundPupil ? 1 : 0) { [weak self] i in self?.spec.roundPupil = i == 1; self?.changed() }],
            [label("Взгляд"), segments(["Открытый", "С прищуром"], spec.squint ? 1 : 0) { [weak self] i in self?.spec.squint = i == 1; self?.changed() }],
            [header("Телосложение"), NSGridCell.emptyContentView],
            [label("Размер"), slider(0.7, 1.15, spec.size, set(\.size))],
            [label("Упитанность"), slider(0.95, 1.45, spec.chub, set(\.chub))],
            [label("Лапы"), slider(8, 15, spec.leg, set(\.leg))],
            [label("Хвост"), slider(18, 40, spec.tail, set(\.tail))],
            [label("Уши"), slider(9, 18, spec.ears, set(\.ears))],
            [header("Характер"), NSGridCell.emptyContentView],
            [label("Энергия"), slider(0, 1, spec.activity, left: "ленивый", right: "активный", set(\.activity))],
            [label("С другими котами"), slider(0, 1, spec.social, left: "сам по себе", right: "общительный", set(\.social))],
            [header("Что умеет"), NSGridCell.emptyContentView],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for r in [0, 7, 13, 16] {
            grid.cell(atColumnIndex: 0, rowIndex: r).xPlacement = .leading
            grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: r, length: 1))
            if r > 0 { grid.row(at: r).topPadding = 10 }
        }
        // сценки — галочками в две колонки
        var checks: [NSButton] = []
        for (key, title) in CatSpec.allTricks {
            let a = act { [weak self] c in
                guard let self else { return }
                self.spec.tricks.removeAll { $0 == key }
                if (c as! NSButton).state == .on { self.spec.tricks.append(key) }
                self.changed()
            }
            let b = NSButton(checkboxWithTitle: title, target: a, action: #selector(ControlAction.fire(_:)))
            b.state = spec.tricks.contains(key) ? .on : .off
            checks.append(b)
        }
        let half = (checks.count + 1) / 2
        let tricks = NSGridView(views: (0..<half).map { i in [checks[i], i + half < checks.count ? checks[i + half] : NSGridCell.emptyContentView] })
        tricks.rowSpacing = 6
        tricks.columnSpacing = 18

        let right = NSStackView(views: [grid, tricks])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 8

        let content = NSView()
        for v in [left, right] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            left.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            left.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22),
            right.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 28),
            right.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            right.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22)])
        w.contentView = content
        w.setContentSize(content.fittingSize)
        tick()
    }

    /// Удалить этого кота насовсем (после подтверждения).
    func remove() {
        let a = NSAlert()
        a.messageText = "Удалить кота «\(spec.look.name)»?"
        a.informativeText = "Его настройки пропадут. Если хочется просто убрать его с экрана, снимите галочку «Выпустить на экран»."
        a.addButton(withTitle: "Удалить")
        a.addButton(withTitle: "Отмена")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Prefs.specs = Prefs.specs.filter { $0.id != spec.id }
        onChange()
        window?.close()
    }

    /// Пересобрать окно на том же месте (после «Случайного кота»).
    func rebuild() {
        guard let old = window else { return }
        let origin = NSPoint(x: old.frame.minX, y: old.frame.maxY)
        old.delegate = nil
        old.orderOut(nil)
        build()
        window?.setFrameTopLeftPoint(origin)
        window?.makeKeyAndOrderFront(nil)
    }

    func controlTextDidChange(_ note: Notification) {
        guard let f = note.object as? NSTextField else { return }
        spec.name = String(f.stringValue.prefix(24))
        changed()
    }
}
