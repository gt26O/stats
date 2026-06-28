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
// DEUX boutons dédiés dans la barre de menus (chacun ouvre sa page) :
//   - "Résumé" (icône speedometer) -> Page 1 : CPU / GPU / RAM (jauge + chiffres +
//     app la plus gourmande + bouton "Détails" vers la page officielle).
//   - "Tableau de bord" (icône grille) -> Page 2 : infos système + cartes détaillées
//     CPU/GPU/RAM + tous les autres modules (leurs "portals").
//
// L'affichage de chaque bouton se règle dans Réglages -> Résumé. Les valeurs sont
// lues via DB.shared (API publique) : aucun fichier de module n'est modifié.
//
// Pour désactiver la vue : retirer la propriété `resumeView` dans AppDelegate.

internal class ResumeView: NSObject {
    private var summaryItem: NSStatusItem? = nil
    private var dashboardItem: NSStatusItem? = nil
    private var summaryPopup: PopupWindow? = nil
    private var dashboardPopup: PopupWindow? = nil

    override init() {
        super.init()

        let summary = ResumePopup()
        summary.onDetails = { [weak self] name in self?.openModule(name) }

        self.summaryPopup = PopupWindow(title: "Résumé", module: .combined, view: summary) { _ in }
        self.dashboardPopup = PopupWindow(title: "Tableau de bord", module: .combined, view: DashboardPopup()) { _ in }

        // Les boutons sont créés au prochain tour de la run loop, une fois que
        // l'application a fini de se lancer et que la barre de menus existe.
        DispatchQueue.main.async { [weak self] in
            self?.reconcileButtons()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(reconcileButtons), name: .resumeConfigChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .resumeConfigChanged, object: nil)
    }

    // Crée ou supprime chaque bouton selon les réglages (appelé au lancement et à
    // chaque changement de réglage).
    @objc public func reconcileButtons() {
        // Bouton 1 : Résumé (page 1).
        if ResumeConfig.button1Visible, self.summaryItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "StatsResumeSummary"
            item.button?.image = iconFromSymbol(name: "speedometer", scale: .large)
            item.button?.toolTip = "Résumé CPU · GPU · RAM"
            item.button?.target = self
            item.button?.action = #selector(self.toggleSummary)
            item.button?.sendAction(on: [.leftMouseDown])
            self.summaryItem = item
        } else if !ResumeConfig.button1Visible, let item = self.summaryItem {
            self.summaryPopup?.setIsVisible(false)
            NSStatusBar.system.removeStatusItem(item)
            self.summaryItem = nil
        }

        // Bouton 2 : Tableau de bord (page 2).
        if ResumeConfig.button2Visible, self.dashboardItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "StatsResumeDashboard"
            item.button?.image = iconFromSymbol(name: "square.grid.2x2", scale: .large)
            item.button?.toolTip = "Tableau de bord complet"
            item.button?.target = self
            item.button?.action = #selector(self.toggleDashboard)
            item.button?.sendAction(on: [.leftMouseDown])
            self.dashboardItem = item
        } else if !ResumeConfig.button2Visible, let item = self.dashboardItem {
            self.dashboardPopup?.setIsVisible(false)
            NSStatusBar.system.removeStatusItem(item)
            self.dashboardItem = nil
        }
    }

    @objc private func toggleSummary(_ sender: NSButton) {
        self.toggle(self.summaryPopup, from: self.summaryItem)
    }
    @objc private func toggleDashboard(_ sender: NSButton) {
        self.toggle(self.dashboardPopup, from: self.dashboardItem)
    }

    // Ouvre la page complète officielle d'un module (CPU/GPU/RAM).
    private func openModule(_ name: String) {
        self.summaryPopup?.setIsVisible(false)
        guard let window = self.summaryItem?.button?.window else { return }
        NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
            "module": name,
            "origin": window.frame.origin,
            "center": window.frame.width / 2
        ])
    }

    private func toggle(_ popup: PopupWindow?, from item: NSStatusItem?) {
        guard let popup, let window = item?.button?.window else { return }
        let openedWindows = NSApplication.shared.windows.filter { $0 is NSPanel }
        openedWindows.forEach { $0.setIsVisible(false) }

        if popup.occlusionState.rawValue == 8192 {
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

// MARK: - Réglages des vues perso (page 1 « Résumé » + page 2 « Tableau de bord »)
//
// Tout est mémorisé dans Store.shared et géré depuis la fenêtre Réglages de Stats
// (entrée « Résumé » de la barre latérale → ResumeSettingsView). Quand un réglage
// change, on poste `.resumeConfigChanged` pour que les deux popups se reconstruisent.

extension Notification.Name {
    static let resumeConfigChanged = Notification.Name("resumeConfigChanged")
}

enum ResumeConfig {
    // Boutons de la barre de menus (afficher / masquer chaque icône).
    static var button1Visible: Bool {
        get { Store.shared.bool(key: "resume_button1_visible", defaultValue: true) }
        set { Store.shared.set(key: "resume_button1_visible", value: newValue) }
    }
    static var button2Visible: Bool {
        get { Store.shared.bool(key: "resume_button2_visible", defaultValue: true) }
        set { Store.shared.set(key: "resume_button2_visible", value: newValue) }
    }

    // Page 1 — Résumé
    static let page1Modules = [ModuleType.CPU.stringValue, ModuleType.GPU.stringValue, ModuleType.RAM.stringValue]
    static func page1Module(_ name: String) -> Bool { Store.shared.bool(key: "resume_page1_\(name)_visible", defaultValue: true) }
    static func setPage1Module(_ name: String, _ value: Bool) { Store.shared.set(key: "resume_page1_\(name)_visible", value: value) }
    static var page1TopApps: Bool {
        get { Store.shared.bool(key: "resume_page1_topapps", defaultValue: true) }
        set { Store.shared.set(key: "resume_page1_topapps", value: newValue) }
    }

    // Page 2 — Tableau de bord : un module = une carte (son "portal"). Clé partagée.
    static func page2Module(_ name: String) -> Bool { Store.shared.bool(key: "resume_dashboard_\(name)_visible", defaultValue: true) }
    static func setPage2Module(_ name: String, _ value: Bool) { Store.shared.set(key: "resume_dashboard_\(name)_visible", value: value) }
    static var page2SystemInfo: Bool {
        get { Store.shared.bool(key: "resume_dashboard_sysinfo", defaultValue: true) }
        set { Store.shared.set(key: "resume_dashboard_sysinfo", value: newValue) }
    }
    static var page2Columns: Int {
        get { max(1, min(3, Store.shared.int(key: "resume_dashboard_columns", defaultValue: 2))) }
        set { Store.shared.set(key: "resume_dashboard_columns", value: newValue) }
    }

    static func notifyChanged() {
        NotificationCenter.default.post(name: .resumeConfigChanged, object: nil)
    }
}

// Page 1 : le carré "Résumé" (CPU / GPU / RAM alignés, sans graphe).
private class ResumePopup: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil

    var onDetails: ((String) -> Void)? = nil

    private var rows: [ModuleSummaryRow] = []
    private var timer: Timer? = nil

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .width
        self.spacing = 6
        self.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        self.rebuild()

        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .resumeConfigChanged, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .resumeConfigChanged, object: nil)
    }

    // (Re)construit les lignes selon les réglages (modules cochés + top apps).
    @objc private func rebuild() {
        self.rows.removeAll()
        self.arrangedSubviews.forEach { self.removeArrangedSubview($0); $0.removeFromSuperview() }

        let palette: [String: NSColor] = [
            ModuleType.CPU.stringValue: .systemBlue,
            ModuleType.GPU.stringValue: .systemPurple,
            ModuleType.RAM.stringValue: .systemOrange
        ]
        let showTopApps = ResumeConfig.page1TopApps

        for name in ResumeConfig.page1Modules where ResumeConfig.page1Module(name) {
            let row = ModuleSummaryRow(moduleName: name, accent: palette[name] ?? .systemBlue, showTopApps: showTopApps) { [weak self] in
                self?.onDetails?(name)
            }
            self.rows.append(row)
            self.addArrangedSubview(row)
        }

        if self.rows.isEmpty {
            let empty = NSTextField(labelWithString: "Aucun module. Activez-les dans Réglages → Résumé.")
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            self.addArrangedSubview(empty)
        }

        let rowsHeight = self.rows.isEmpty
            ? 20
            : CGFloat(self.rows.count) * ModuleSummaryRow.height(showTopApps: showTopApps)
        let count = max(self.rows.count, 1)
        let total = rowsHeight + self.spacing * CGFloat(max(count - 1, 0)) + 8
        self.setFrameSize(NSSize(width: self.frame.width, height: total))
        self.sizeCallback?(self.frame.size)
        self.update()
    }

    fileprivate func settings() -> NSView? { return nil }
    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) { self.keyboardShortcut = binding }

    // Rafraîchit en continu tant que le popup est ouvert.
    fileprivate func appear() {
        self.rebuild()
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

// Une ligne de la page "Résumé" pour un module : que des données texte, collées à
// gauche et prenant toute la largeur (pas de jauge / graphe).
private final class ModuleSummaryRow: NSView {
    static func height(showTopApps: Bool) -> CGFloat { showTopApps ? 58 : 40 }

    private let moduleName: String
    private let accent: NSColor
    private let showTopApps: Bool
    private let onDetails: () -> Void

    private let nameField: NSTextField
    private let figuresField: NSTextField
    private let processField: NSTextField

    init(moduleName: String, accent: NSColor, showTopApps: Bool, onDetails: @escaping () -> Void) {
        self.moduleName = moduleName
        self.accent = accent
        self.showTopApps = showTopApps
        self.onDetails = onDetails

        self.nameField = NSTextField(labelWithString: localizedString(moduleName))
        self.figuresField = NSTextField(labelWithString: "—")
        self.processField = NSTextField(labelWithString: "")

        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: ModuleSummaryRow.height(showTopApps: showTopApps)))

        // Largeur et hauteur fixes : toutes les lignes sont identiques et leur
        // contenu démarre exactement au même x (10) -> les 3 modules sont alignés.
        self.translatesAutoresizingMaskIntoConstraints = false
        self.widthAnchor.constraint(equalToConstant: Constants.Popup.width).isActive = true
        self.heightAnchor.constraint(equalToConstant: ModuleSummaryRow.height(showTopApps: showTopApps)).isActive = true

        self.nameField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.nameField.textColor = self.accent
        self.nameField.alignment = .left
        self.figuresField.font = NSFont.systemFont(ofSize: 12)
        self.figuresField.textColor = .labelColor
        self.figuresField.alignment = .left
        self.figuresField.lineBreakMode = .byTruncatingTail
        self.processField.font = NSFont.systemFont(ofSize: 11)
        self.processField.textColor = .secondaryLabelColor
        self.processField.alignment = .left
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
        detailsButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        [self.nameField, self.figuresField, self.processField, detailsButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview($0)
        }

        NSLayoutConstraint.activate([
            self.nameField.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
            self.nameField.topAnchor.constraint(equalTo: self.topAnchor, constant: 5),

            detailsButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10),
            detailsButton.centerYAnchor.constraint(equalTo: self.nameField.centerYAnchor),
            self.nameField.trailingAnchor.constraint(lessThanOrEqualTo: detailsButton.leadingAnchor, constant: -6),

            self.figuresField.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
            self.figuresField.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10),
            self.figuresField.topAnchor.constraint(equalTo: self.nameField.bottomAnchor, constant: 2)
        ])

        if showTopApps {
            NSLayoutConstraint.activate([
                self.processField.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
                self.processField.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10),
                self.processField.topAnchor.constraint(equalTo: self.figuresField.bottomAnchor, constant: 2)
            ])
        } else {
            self.processField.removeFromSuperview()
        }
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
            var figures: [String] = []
            if let load = DB.shared.findOne(CPU_Load.self, key: "CPU@LoadReader") {
                figures.append("\(Int((load.totalUsage * 100).rounded())) %")
            }
            if let temp = DB.shared.findOne(Double.self, key: "CPU@TemperatureReader"), temp > 0 {
                figures.append(temperature(temp))
            }
            if let cores = SystemKit.shared.device.info.cpu?.logicalCores {
                figures.append("\(cores) cœurs")
            }
            self.figuresField.stringValue = figures.joined(separator: "   ·   ")
            if self.showTopApps {
                self.processField.stringValue = self.topProcessesPercent(key: "CPU@ProcessReader")
            }
        case ModuleType.GPU.stringValue:
            if let gpus = DB.shared.findOne(GPUs.self, key: "GPU@InfoReader"),
               let gpu = gpus.list.first(where: { $0.state }) ?? gpus.list.first {
                var figures: [String] = ["\(Int(((gpu.utilization ?? 0) * 100).rounded())) %"]
                figures.append(gpu.model)
                if let temp = gpu.temperature, temp > 0 { figures.append(temperature(temp)) }
                self.figuresField.stringValue = figures.joined(separator: "   ·   ")
            }
            // macOS n'expose pas l'usage GPU par application.
            if self.showTopApps {
                self.processField.stringValue = "Détail par application indisponible"
            }
        case ModuleType.RAM.stringValue:
            if let ram = DB.shared.findOne(RAM_Usage.self, key: "RAM@UsageReader") {
                let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
                let used = Units(bytes: Int64(ram.usage * totalBytes)).getReadableMemory(style: .memory)
                let total = Units(bytes: Int64(totalBytes)).getReadableMemory(style: .memory)
                self.figuresField.stringValue = "\(Int((ram.usage * 100).rounded())) %   ·   \(used) / \(total)"
            }
            if self.showTopApps {
                self.processField.stringValue = self.topProcessesMemory(key: "RAM@ProcessReader")
            }
        default: break
        }
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

// MARK: - Page 2 : tableau de bord complet (réécriture perso)
//
// En-tête système (modèle · macOS · uptime) + grille de cartes sur 2 ou 3 colonnes.
// TOUTES les sections ont le même style / la même UX : chaque module (y compris
// CPU/GPU/RAM) est présenté via son "portal" officiel. Ce qui s'affiche se règle
// dans Réglages → Résumé (ResumeSettingsView) ; un `.resumeConfigChanged` reconstruit.
//
// Limitation : les "portals" sont partagés avec l'option native "Combined
// modules" de Stats -> éviter d'afficher les deux en même temps.

private final class DashboardPopup: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil

    private static let gap: CGFloat = 8
    private static let insets: CGFloat = 8

    private var systemInfoField: NSTextField? = nil
    private var timer: Timer? = nil

    private var columns: Int { ResumeConfig.page2Columns }
    private var contentWidth: CGFloat {
        Constants.Popup.width * CGFloat(self.columns) + DashboardPopup.gap * CGFloat(self.columns - 1)
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width * 2 + DashboardPopup.gap, height: 0))

        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .width
        self.spacing = 8
        self.edgeInsets = NSEdgeInsets(top: DashboardPopup.insets, left: 0, bottom: DashboardPopup.insets, right: 0)

        self.rebuild()

        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .toggleModule, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .resumeConfigChanged, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleModule, object: nil)
        NotificationCenter.default.removeObserver(self, name: .resumeConfigChanged, object: nil)
    }

    fileprivate func settings() -> NSView? { return nil }
    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) { self.keyboardShortcut = binding }

    fileprivate func appear() {
        self.rebuild()
        self.refresh()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }
    fileprivate func disappear() {
        self.timer?.invalidate()
        self.timer = nil
    }

    private func refresh() {
        self.systemInfoField?.stringValue = DashboardPopup.systemInfoText()
    }

    @objc private func rebuild() {
        self.systemInfoField = nil
        self.arrangedSubviews.forEach { self.removeArrangedSubview($0); $0.removeFromSuperview() }

        let width = self.contentWidth
        var children: [(view: NSView, height: CGFloat)] = []

        // En-tête infos système (modèle · macOS · uptime).
        if ResumeConfig.page2SystemInfo {
            children.append((self.headerView(), 22))
        }

        // Toutes les sections cochées sont présentées de façon IDENTIQUE : on réutilise
        // le "portal" de chaque module (même style, même UX pour tous les modules).
        let portals = modules.filter {
            $0.enabled && $0.available && $0.portal != nil && ResumeConfig.page2Module($0.config.name)
        }.compactMap { $0.portal as? NSView }

        var i = 0
        while i < portals.count {
            var rowViews: [NSView] = []
            for c in 0..<self.columns {
                rowViews.append(self.card(i + c < portals.count ? portals[i + c] : nil))
            }
            children.append((self.gridRow(rowViews), Constants.Popup.portalHeight))
            i += self.columns
        }

        if portals.isEmpty {
            let empty = NSTextField(labelWithString: "Aucune section. Activez-en dans Réglages → Résumé.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            children.append((empty, 24))
        }

        children.forEach { self.addArrangedSubview($0.view) }

        let n = children.count
        let total = DashboardPopup.insets * 2
            + children.reduce(0) { $0 + $1.height }
            + self.spacing * CGFloat(max(n - 1, 0))
        self.setFrameSize(NSSize(width: width, height: total))
        self.sizeCallback?(self.frame.size)
    }

    // En-tête : une seule ligne d'infos système, collée à gauche (se met à jour : uptime).
    private func headerView() -> NSView {
        let info = NSTextField(labelWithString: DashboardPopup.systemInfoText())
        info.font = .systemFont(ofSize: 12)
        info.textColor = .secondaryLabelColor
        info.alignment = .left
        info.lineBreakMode = .byTruncatingTail
        self.systemInfoField = info

        // [info, espace] -> l'info reste collée à gauche, l'espace mange le reste.
        let row = NSStackView(views: [info, NSView()])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 0
        row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return row
    }

    // Infos système publiques : modèle de Mac · version macOS · cœurs · uptime.
    private static func systemInfoText() -> String {
        let d = SystemKit.shared.device
        var parts: [String] = [d.model.name]
        if let os = d.os {
            parts.append("\(os.name) \(os.version.majorVersion).\(os.version.minorVersion)")
        }
        if let cores = d.info.cpu?.logicalCores {
            parts.append("\(cores) cœurs")
        }
        if let boot = d.bootDate {
            parts.append("Allumé depuis " + DashboardPopup.uptimeText(Date().timeIntervalSince(boot)))
        }
        return parts.joined(separator: "   ·   ")
    }

    private static func uptimeText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let days = s / 86400, hours = (s % 86400) / 3600, mins = (s % 3600) / 60
        if days > 0 { return "\(days) j \(hours) h" }
        if hours > 0 { return "\(hours) h \(mins) min" }
        return "\(mins) min"
    }

    // Une ligne de la grille = `columns` cartes (les dernières peuvent être vides pour aligner).
    private func gridRow(_ views: [NSView]) -> NSView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        row.spacing = DashboardPopup.gap
        row.heightAnchor.constraint(equalToConstant: Constants.Popup.portalHeight).isActive = true
        return row
    }

    // Conteneur d'une carte : enveloppe un portal (ou un vide pour garder l'alignement).
    private func card(_ view: NSView?) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: Constants.Popup.portalHeight).isActive = true
        guard let view else { return container }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }
}

// MARK: - Réglages des vues "Résumé" (affiché dans la fenêtre Réglages de Stats)
//
// Panneau qui gère les DEUX pages perso : la page 1 « Résumé » et la page 2
// « Tableau de bord ». Chaque changement est mémorisé (ResumeConfig) puis diffusé
// via `.resumeConfigChanged`, ce qui reconstruit les popups ouverts.
internal final class ResumeSettingsView: NSStackView {
    private let content = ScrollableStackView(orientation: .vertical)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Settings.width, height: Constants.Settings.height))
        self.translatesAutoresizingMaskIntoConstraints = false
        self.orientation = .vertical

        self.content.stackView.edgeInsets = NSEdgeInsets(
            top: 0,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )
        self.content.stackView.spacing = Constants.Settings.margin

        self.addArrangedSubview(self.content)
        self.build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Reconstruit les sections (appelé à chaque ouverture pour refléter l'état réel).
    internal func viewWillAppear() {
        self.build()
    }

    private func build() {
        self.content.stackView.subviews.forEach { $0.removeFromSuperview() }

        // --- Boutons dans la barre de menus (icônes en haut de l'écran) ---
        self.content.stackView.addArrangedSubview(PreferencesSection(
            title: "Icônes dans la barre des menus",
            subtitle: "Un bouton par page",
            [
                PreferencesRow("Bouton « Résumé » (CPU · GPU · RAM)", component: self.switchView(
                    action: #selector(self.toggleButton1), state: ResumeConfig.button1Visible
                )),
                PreferencesRow("Bouton « Tableau de bord »", component: self.switchView(
                    action: #selector(self.toggleButton2), state: ResumeConfig.button2Visible
                ))
            ]
        ))

        // --- Page 1 : Résumé (CPU / GPU / RAM) ---
        var page1: [NSView] = []
        for name in ResumeConfig.page1Modules {
            let sw = self.switchView(action: #selector(self.togglePage1Module), state: ResumeConfig.page1Module(name))
            sw.identifier = NSUserInterfaceItemIdentifier(rawValue: name)
            page1.append(PreferencesRow(localizedString(name), id: name, component: sw))
        }
        page1.append(PreferencesRow(
            "Afficher l'application la plus gourmande",
            component: self.switchView(action: #selector(self.toggleTopApps), state: ResumeConfig.page1TopApps)
        ))
        self.content.stackView.addArrangedSubview(PreferencesSection(
            title: "Page « Résumé » — modules affichés",
            page1
        ))

        // --- Page 2 : Tableau de bord (affichage) ---
        let columns = self.selectView(
            action: #selector(self.selectColumns),
            items: [KeyValue_t(key: "2", value: "2 colonnes"), KeyValue_t(key: "3", value: "3 colonnes")],
            selected: "\(ResumeConfig.page2Columns)"
        )
        self.content.stackView.addArrangedSubview(PreferencesSection(
            title: "Tableau de bord — présentation",
            [
                PreferencesRow("Disposition", component: columns),
                PreferencesRow("Infos système (modèle · macOS · uptime)", component: self.switchView(
                    action: #selector(self.toggleSystemInfo), state: ResumeConfig.page2SystemInfo
                ))
            ]
        ))

        // --- Page 2 : sections (un module = une carte) ---
        var sections: [NSView] = []
        for m in modules where m.available && m.portal != nil {
            let title = m.enabled
                ? localizedString(m.config.name)
                : localizedString(m.config.name) + " — module désactivé"
            let sw = self.switchView(action: #selector(self.togglePage2Module), state: ResumeConfig.page2Module(m.config.name))
            sw.identifier = NSUserInterfaceItemIdentifier(rawValue: m.config.name)
            sw.isEnabled = m.enabled
            sections.append(PreferencesRow(title, id: m.config.name, component: sw))
        }
        if sections.isEmpty {
            let label = NSTextField(labelWithString: "Aucun module disponible.")
            label.textColor = .secondaryLabelColor
            sections.append(PreferencesRow(component: label))
        }
        self.content.stackView.addArrangedSubview(PreferencesSection(
            title: "Tableau de bord — sections affichées",
            subtitle: "Ajouter ou enlever des cartes",
            sections
        ))
    }

    @objc private func togglePage1Module(_ sender: NSSwitch) {
        guard let name = sender.identifier?.rawValue else { return }
        ResumeConfig.setPage1Module(name, sender.state == .on)
        ResumeConfig.notifyChanged()
    }
    @objc private func toggleTopApps(_ sender: NSSwitch) {
        ResumeConfig.page1TopApps = sender.state == .on
        ResumeConfig.notifyChanged()
    }
    @objc private func toggleButton1(_ sender: NSSwitch) {
        ResumeConfig.button1Visible = sender.state == .on
        ResumeConfig.notifyChanged()
    }
    @objc private func toggleButton2(_ sender: NSSwitch) {
        ResumeConfig.button2Visible = sender.state == .on
        ResumeConfig.notifyChanged()
    }
    @objc private func toggleSystemInfo(_ sender: NSSwitch) {
        ResumeConfig.page2SystemInfo = sender.state == .on
        ResumeConfig.notifyChanged()
    }
    @objc private func togglePage2Module(_ sender: NSSwitch) {
        guard let name = sender.identifier?.rawValue else { return }
        ResumeConfig.setPage2Module(name, sender.state == .on)
        ResumeConfig.notifyChanged()
    }
    @objc private func selectColumns(_ sender: NSPopUpButton) {
        guard let key = sender.selectedItem?.representedObject as? String, let value = Int(key) else { return }
        ResumeConfig.page2Columns = value
        ResumeConfig.notifyChanged()
    }
}
