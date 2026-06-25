//
//  CombinedView.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 09/01/2023
//  Using Swift 5.0
//  Running on macOS 13.1
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

// Imports nécessaires à la vue "Résumé" (ajout perso) pour lire les valeurs
// publiées par les modules (CPU_Load, RAM_Usage, GPUs) via DB.shared.
import CPU
import GPU
import RAM

internal class CombinedView: NSObject, NSGestureRecognizerDelegate {
    private var menuBarItem: NSStatusItem? = nil
    private var view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: Constants.Widget.height))
    private var popup: PopupWindow? = nil
    
    private var status: Bool {
        Store.shared.bool(key: "CombinedModules", defaultValue: false)
    }
    private var spacing: CGFloat {
        CGFloat(Int(Store.shared.string(key: "CombinedModules_spacing", defaultValue: "")) ?? 0)
    }
    private var separator: Bool {
        Store.shared.bool(key: "CombinedModules_separator", defaultValue: false)
    }
    
    private var activeModules: [Module] {
        modules.filter({ $0.enabled }).sorted(by: { $0.combinedPosition < $1.combinedPosition })
    }
    
    private var combinedModulesPopup: Bool {
        get { Store.shared.bool(key: "CombinedModules_popup", defaultValue: true) }
        set { Store.shared.set(key: "CombinedModules_popup", value: newValue) }
    }
    
    override init() {
        super.init()
        
        modules.forEach { (m: Module) in
            m.menuBar.callback = { [weak self] in
                if let s = self?.status, s {
                    DispatchQueue.main.async(execute: {
                        self?.recalculate()
                    })
                }
            }
        }
        
        self.popup = PopupWindow(title: "Combined modules", module: .combined, view: Popup()) { _ in }
        
        if self.status {
            self.enable()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(listenForOneView), name: .toggleOneView, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenForModuleRearrrange), name: .moduleRearrange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenCombinedModulesPopup), name: .combinedModulesPopup, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenForModule), name: .toggleModule, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleOneView, object: nil)
        NotificationCenter.default.removeObserver(self, name: .moduleRearrange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .combinedModulesPopup, object: nil)
        NotificationCenter.default.removeObserver(self, name: .toggleModule, object: nil)
    }
    
    public func enable() {
        self.menuBarItem = NSStatusBar.system.statusItem(withLength: 0)
        DispatchQueue.main.async(execute: {
            self.menuBarItem?.autosaveName = "CombinedModules"
        })
        self.menuBarItem?.button?.addSubview(self.view)
        self.menuBarItem?.button?.image = NSImage()
        self.menuBarItem?.button?.toolTip = localizedString("Combined modules")
        
        if !self.combinedModulesPopup {
            self.activeModules.forEach { (m: Module) in
                m.menuBar.widgets.forEach { w in
                    w.item.onClick = {
                        if let window = w.item.window {
                            NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
                                "module": m.name,
                                "widget": w.type,
                                "origin": window.frame.origin,
                                "center": window.frame.width/2
                            ])
                        }
                    }
                }
            }
        } else {
            self.menuBarItem?.button?.target = self
            self.menuBarItem?.button?.action = #selector(self.togglePopup)
            self.menuBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        
        DispatchQueue.main.async(execute: {
            self.recalculate()
        })
    }
    
    public func disable() {
        self.activeModules.forEach { (m: Module) in
            m.menuBar.widgets.forEach { w in
                w.item.onClick = nil
            }
        }
        if let item = self.menuBarItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.menuBarItem = nil
    }
    
    private func recalculate() {
        self.view.subviews.forEach({ $0.removeFromSuperview() })
        
        var w: CGFloat = 0
        var i: Int = 0
        self.activeModules.forEach { (m: Module) in
            self.view.addSubview(m.menuBar.view)
            self.view.subviews[i].setFrameOrigin(NSPoint(x: w, y: 0))
            w += m.menuBar.view.frame.width + self.spacing
            i += 1
            
            if self.separator && i < 2 * self.activeModules.count - 1 {
                let separator = NSView(frame: NSRect(x: w, y: 3, width: 1, height: Constants.Widget.height-6))
                separator.wantsLayer = true
                separator.layer?.backgroundColor = (separator.isDarkMode ? NSColor.white : NSColor.black).cgColor
                self.view.addSubview(separator)
                w += 3 + self.spacing
                i += 1
            }
        }
        self.view.setFrameSize(NSSize(width: w, height: self.view.frame.height))
        self.menuBarItem?.length = w
    }
    
    // call when popup appear/disappear
    private func visibilityCallback(_ state: Bool) {}
    
    @objc private func togglePopup(_ sender: NSButton) {
        guard let popup = self.popup, let item = self.menuBarItem, let window = item.button?.window else { return }
        let openedWindows = NSApplication.shared.windows.filter{ $0 is NSPanel }
        openedWindows.forEach{ $0.setIsVisible(false) }
        
        if popup.occlusionState.rawValue == 8192 {
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            popup.contentView?.invalidateIntrinsicContentSize()
            
            let windowCenter = popup.contentView!.intrinsicContentSize.width / 2
            var x = window.frame.origin.x - windowCenter + window.frame.width/2
            let y = window.frame.origin.y - popup.contentView!.intrinsicContentSize.height - 3
            
            let maxWidth = NSScreen.screens.map{ $0.frame.width }.reduce(0, +)
            if x + popup.contentView!.intrinsicContentSize.width > maxWidth {
                x = maxWidth - popup.contentView!.intrinsicContentSize.width - 3
            }
            
            popup.setFrameOrigin(NSPoint(x: x, y: y))
            popup.setIsVisible(true)
        } else {
            popup.setIsVisible(false)
        }
    }
    
    @objc private func listenForOneView(_ notification: Notification) {
        guard notification.userInfo?["module"] == nil else { return }
        
        if self.status {
            self.enable()
        } else {
            self.disable()
        }
    }
    
    @objc private func listenForModuleRearrrange() {
        self.recalculate()
    }
    
    @objc private func listenCombinedModulesPopup() {
        if !self.combinedModulesPopup {
            self.activeModules.forEach { (m: Module) in
                m.menuBar.widgets.forEach { w in
                    w.item.onClick = {
                        if let window = w.item.window {
                            NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
                                "module": m.name,
                                "widget": w.type,
                                "origin": window.frame.origin,
                                "center": window.frame.width/2
                            ])
                        }
                    }
                }
            }
            self.menuBarItem?.button?.action = nil
        } else {
            self.activeModules.forEach { (m: Module) in
                m.menuBar.widgets.forEach { w in
                    w.item.onClick = nil
                }
            }
            
            self.menuBarItem?.button?.target = self
            self.menuBarItem?.button?.action = #selector(self.togglePopup)
            self.menuBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
    }
    
    @objc private func listenForModule(_ notification: Notification) {
        guard let name = notification.userInfo?["module"] as? String,
              let state = notification.userInfo?["state"] as? Bool,
              state,
              let module = self.activeModules.first(where: { $0.name == name }) else { return }
        
        module.menuBar.widgets.forEach { w in
            w.item.onClick = {
                if let window = w.item.window {
                    NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
                        "module": module.name,
                        "widget": w.type,
                        "origin": window.frame.origin,
                        "center": window.frame.width/2
                    ])
                }
            }
        }
    }
}

private class Popup: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil
    
    init() {
        self.keyboardShortcut = Store.shared.array(key: "CombinedModules_popup_keyboardShortcut", defaultValue: []) as? [UInt16] ?? []
        
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .width
        self.spacing = Constants.Popup.spacing
        
        self.reinit()
        
        NotificationCenter.default.addObserver(self, selector: #selector(reinit), name: .toggleModule, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleOneView, object: nil)
    }
    
    fileprivate func settings() -> NSView? { return nil }
    fileprivate func appear() {}
    fileprivate func disappear() {}
    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "CombinedModules_popup_keyboardShortcut", value: binding)
    }
    
    @objc private func reinit() {
        self.subviews.forEach({ $0.removeFromSuperview() })
        
        let availableModules = modules.filter({ $0.enabled && $0.portal != nil })
        availableModules.forEach { (m: Module) in
            if let p = m.portal {
                self.addArrangedSubview(p)
            }
        }
        
        let h = CGFloat(availableModules.count) * Constants.Popup.portalHeight + (CGFloat(availableModules.count-1)*Constants.Popup.spacing)
        if h > 0 {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
}

// MARK: - Vue "Résumé" (ajout personnel)
//
// Un seul bouton dédié dans la barre de menus (icône "speedometer") qui ouvre :
//   - Page 1 "Résumé" : CPU / GPU / RAM, avec pour chacun une jauge, des chiffres,
//     un mini-graphe d'historique, l'app la plus gourmande, et un bouton "Détails"
//     qui ouvre la page complète officielle du module.
//   - Page 2 "Tableau de bord" : un coup d'œil sur tous les modules activés
//     (réutilise les "portals" fournis par chaque module).
//
// Les valeurs sont lues via DB.shared (API publique), donc AUCUN fichier de
// module n'est modifié. Tout est isolé ici + 1 ligne dans AppDelegate, pour
// limiter les conflits lors des mises à jour d'exelban/stats.
//
// Pour désactiver la vue : retirer la propriété `resumeView` dans AppDelegate.

internal class ResumeView: NSObject {
    private var menuBarItem: NSStatusItem? = nil
    private var summaryPopup: PopupWindow? = nil
    private var dashboardPopup: PopupWindow? = nil

    override init() {
        super.init()

        let summary = ResumePopup()
        summary.onDetails = { [weak self] name in self?.openModule(name) }
        summary.onDashboard = { [weak self] in self?.openDashboard() }

        self.summaryPopup = PopupWindow(title: "Résumé", module: .combined, view: summary) { _ in }
        self.dashboardPopup = PopupWindow(title: "Tableau de bord", module: .combined, view: DashboardPopup()) { _ in }

        // Le bouton est créé au prochain tour de la run loop, une fois que
        // l'application a fini de se lancer et que la barre de menus existe.
        DispatchQueue.main.async { [weak self] in
            self?.enable()
        }
    }

    public func enable() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "StatsResume"
        item.button?.image = iconFromSymbol(name: "speedometer", scale: .large)
        item.button?.toolTip = "Résumé CPU · GPU · RAM"
        item.button?.target = self
        item.button?.action = #selector(self.toggleSummary)
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        self.menuBarItem = item
    }

    public func disable() {
        if let item = self.menuBarItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.menuBarItem = nil
    }

    @objc private func toggleSummary(_ sender: NSButton) {
        self.toggle(self.summaryPopup)
    }

    // Ouvre la page 2 (tableau de bord) à la place de la page 1.
    private func openDashboard() {
        self.summaryPopup?.setIsVisible(false)
        self.toggle(self.dashboardPopup, forceOpen: true)
    }

    // Ouvre la page complète officielle d'un module (CPU/GPU/RAM).
    private func openModule(_ name: String) {
        self.summaryPopup?.setIsVisible(false)
        guard let window = self.menuBarItem?.button?.window else { return }
        NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
            "module": name,
            "origin": window.frame.origin,
            "center": window.frame.width / 2
        ])
    }

    private func toggle(_ popup: PopupWindow?, forceOpen: Bool = false) {
        guard let popup, let window = self.menuBarItem?.button?.window else { return }
        let openedWindows = NSApplication.shared.windows.filter { $0 is NSPanel }
        openedWindows.forEach { $0.setIsVisible(false) }

        if popup.occlusionState.rawValue == 8192 || forceOpen {
            NSApplication.shared.activate(ignoringOtherApps: true)

            popup.contentView?.invalidateIntrinsicContentSize()

            let windowCenter = popup.contentView!.intrinsicContentSize.width / 2
            var x = window.frame.origin.x - windowCenter + window.frame.width / 2
            let y = window.frame.origin.y - popup.contentView!.intrinsicContentSize.height - 3

            let maxWidth = NSScreen.screens.map { $0.frame.width }.reduce(0, +)
            if x + popup.contentView!.intrinsicContentSize.width > maxWidth {
                x = maxWidth - popup.contentView!.intrinsicContentSize.width - 3
            }

            popup.setFrameOrigin(NSPoint(x: x, y: y))
            popup.setIsVisible(true)
        } else {
            popup.setIsVisible(false)
        }
    }
}

// Page 1 : le carré "Résumé" (CPU / GPU / RAM enrichis).
private class ResumePopup: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil

    var onDetails: ((String) -> Void)? = nil
    var onDashboard: (() -> Void)? = nil

    private var rows: [ModuleSummaryRow] = []
    private var timer: Timer? = nil

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .width
        self.spacing = 6
        self.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        self.build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        let configs: [(name: String, color: NSColor)] = [
            (ModuleType.CPU.stringValue, NSColor.systemBlue),
            (ModuleType.GPU.stringValue, NSColor.systemPurple),
            (ModuleType.RAM.stringValue, NSColor.systemOrange)
        ]

        for cfg in configs {
            let row = ModuleSummaryRow(moduleName: cfg.name, accent: cfg.color) { [weak self] in
                self?.onDetails?(cfg.name)
            }
            self.rows.append(row)
            self.addArrangedSubview(row)
        }

        let footer = NSButton()
        footer.title = "Tableau de bord complet"
        footer.bezelStyle = .rounded
        footer.target = self
        footer.action = #selector(self.dashboardAction)
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.heightAnchor.constraint(equalToConstant: 28).isActive = true
        self.addArrangedSubview(footer)

        let total = CGFloat(self.rows.count) * ModuleSummaryRow.height
            + 28
            + self.spacing * CGFloat(self.rows.count)
            + 8
        self.setFrameSize(NSSize(width: self.frame.width, height: total))
    }

    @objc private func dashboardAction() {
        self.onDashboard?()
    }

    fileprivate func settings() -> NSView? { return nil }
    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) { self.keyboardShortcut = binding }

    // Rafraîchit en continu tant que le popup est ouvert.
    fileprivate func appear() {
        self.update()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }
    fileprivate func disappear() {
        self.timer?.invalidate()
        self.timer = nil
    }

    private func update() {
        self.rows.forEach { $0.update() }
    }
}

// Une ligne de la page "Résumé" pour un module (jauge + chiffres + graphe + top app + bouton).
private final class ModuleSummaryRow: NSStackView {
    static let height: CGFloat = 104

    private let moduleName: String
    private let accent: NSColor
    private let onDetails: () -> Void

    private let gauge: PieChartView
    private let nameField: NSTextField
    private let figuresField: NSTextField
    private let processField: NSTextField
    private let chart: LineChartView

    init(moduleName: String, accent: NSColor, onDetails: @escaping () -> Void) {
        self.moduleName = moduleName
        self.accent = accent
        self.onDetails = onDetails

        self.gauge = PieChartView(frame: NSRect(x: 0, y: 0, width: 50, height: 50), segments: [], drawValue: true)
        self.nameField = NSTextField(labelWithString: localizedString(moduleName))
        self.figuresField = NSTextField(labelWithString: "—")
        self.processField = NSTextField(labelWithString: "")
        self.chart = LineChartView(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 22), num: 120, suffix: "%", color: accent)

        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: ModuleSummaryRow.height))

        self.orientation = .vertical
        self.alignment = .width
        self.distribution = .fill
        self.spacing = 3
        self.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        self.heightAnchor.constraint(equalToConstant: ModuleSummaryRow.height).isActive = true

        self.gauge.translatesAutoresizingMaskIntoConstraints = false
        self.gauge.widthAnchor.constraint(equalToConstant: 50).isActive = true
        self.gauge.heightAnchor.constraint(equalToConstant: 50).isActive = true
        self.gauge.setNonActiveSegmentColor(NSColor.tertiaryLabelColor.withAlphaComponent(0.25))

        self.nameField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        self.figuresField.font = NSFont.systemFont(ofSize: 11)
        self.figuresField.textColor = .secondaryLabelColor
        self.figuresField.lineBreakMode = .byTruncatingTail
        self.processField.font = NSFont.systemFont(ofSize: 11)
        self.processField.textColor = .secondaryLabelColor
        self.processField.lineBreakMode = .byTruncatingTail

        let detailsButton = NSButton()
        detailsButton.title = "Détails"
        detailsButton.bezelStyle = .rounded
        detailsButton.controlSize = .small
        detailsButton.font = NSFont.systemFont(ofSize: 11)
        detailsButton.target = self
        detailsButton.action = #selector(self.detailsAction)
        detailsButton.toolTip = "Ouvrir la page complète"
        detailsButton.setContentHuggingPriority(.required, for: .horizontal)

        let titleRow = NSStackView(views: [self.nameField, NSView(), detailsButton])
        titleRow.orientation = .horizontal
        titleRow.distribution = .fill
        titleRow.spacing = 6

        let infoColumn = NSStackView(views: [titleRow, self.figuresField])
        infoColumn.orientation = .vertical
        infoColumn.alignment = .leading
        infoColumn.distribution = .fillEqually
        infoColumn.spacing = 2

        let topLine = NSStackView(views: [self.gauge, infoColumn])
        topLine.orientation = .horizontal
        topLine.alignment = .centerY
        topLine.distribution = .fill
        topLine.spacing = 10
        topLine.translatesAutoresizingMaskIntoConstraints = false
        topLine.heightAnchor.constraint(equalToConstant: 50).isActive = true

        self.chart.translatesAutoresizingMaskIntoConstraints = false
        self.chart.heightAnchor.constraint(equalToConstant: 20).isActive = true

        self.addArrangedSubview(topLine)
        self.addArrangedSubview(self.chart)
        self.addArrangedSubview(self.processField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func detailsAction() {
        self.onDetails()
    }

    // Met à jour la ligne à partir des valeurs publiées dans DB.shared.
    func update() {
        switch self.moduleName {
        case ModuleType.CPU.stringValue:
            if let load = DB.shared.findOne(CPU_Load.self, key: "CPU@LoadReader") {
                self.setGauge(load.totalUsage)
                self.chart.addValue(load.totalUsage)
            }
            var cpuFigures: [String] = []
            if let temp = DB.shared.findOne(Double.self, key: "CPU@TemperatureReader"), temp > 0 {
                cpuFigures.append(temperature(temp))
            }
            if let cores = SystemKit.shared.device.info.cpu?.logicalCores {
                cpuFigures.append("\(cores) cœurs")
            }
            self.figuresField.stringValue = cpuFigures.joined(separator: "   ")
            self.processField.stringValue = self.topProcessesPercent(key: "CPU@ProcessReader")
        case ModuleType.GPU.stringValue:
            if let gpus = DB.shared.findOne(GPUs.self, key: "GPU@InfoReader"),
               let gpu = gpus.list.first(where: { $0.state }) ?? gpus.list.first {
                let util = gpu.utilization ?? 0
                self.setGauge(util)
                self.chart.addValue(util)
                var figures = gpu.model
                if let temp = gpu.temperature, temp > 0 {
                    figures = "\(temperature(temp))   " + figures
                }
                self.figuresField.stringValue = figures
            }
            // macOS n'expose pas l'usage GPU par application.
            self.processField.stringValue = "Détail par application indisponible"
        case ModuleType.RAM.stringValue:
            if let ram = DB.shared.findOne(RAM_Usage.self, key: "RAM@UsageReader") {
                self.setGauge(ram.usage)
                self.chart.addValue(ram.usage)
                let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
                let used = Units(bytes: Int64(ram.usage * totalBytes)).getReadableMemory(style: .memory)
                let total = Units(bytes: Int64(totalBytes)).getReadableMemory(style: .memory)
                self.figuresField.stringValue = "\(used) / \(total)"
            }
            self.processField.stringValue = self.topProcessesMemory(key: "RAM@ProcessReader")
        default: break
        }
    }

    private func setGauge(_ value: Double) {
        self.gauge.setValue(value)
        self.gauge.setSegments([ColorValue(value, color: self.accent)])
    }

    private func topProcessesPercent(key: String) -> String {
        guard let list = DB.shared.findOne([TopProcess].self, key: key), !list.isEmpty else { return "" }
        let top = list.prefix(2).map { "\($0.name) \(Int($0.usage.rounded()))%" }
        return "Top : " + top.joined(separator: "   ")
    }

    private func topProcessesMemory(key: String) -> String {
        guard let list = DB.shared.findOne([TopProcess].self, key: key), !list.isEmpty else { return "" }
        let top = list.prefix(2).map { "\($0.name) \(Units(bytes: Int64($0.usage)).getReadableMemory(style: .memory))" }
        return "Top : " + top.joined(separator: "   ")
    }
}

// Page 2 : tableau de bord = tous les modules activés d'un coup d'œil (réutilise les portals).
private final class DashboardPopup: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .width
        self.spacing = Constants.Popup.spacing

        self.reinit()

        NotificationCenter.default.addObserver(self, selector: #selector(reinit), name: .toggleModule, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleModule, object: nil)
    }

    fileprivate func settings() -> NSView? { return nil }
    fileprivate func appear() { self.reinit() }
    fileprivate func disappear() {}
    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) { self.keyboardShortcut = binding }

    @objc private func reinit() {
        self.subviews.forEach({ $0.removeFromSuperview() })

        let availableModules = modules.filter({ $0.enabled && $0.portal != nil })
        availableModules.forEach { (m: Module) in
            if let p = m.portal {
                self.addArrangedSubview(p)
            }
        }

        let count = availableModules.count
        let h = CGFloat(count) * Constants.Popup.portalHeight + (CGFloat(max(count - 1, 0)) * Constants.Popup.spacing)
        if h > 0 {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
}
