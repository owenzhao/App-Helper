//
//  App_HelperApp.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import SwiftUI
import AppKit
import Defaults
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window:NSWindow?
    private var statusItem:NSStatusItem?
    private var watcher = SystemWatcher.shared
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        registerNotification()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenubarTray()
        
        if #available(macOS 13, *) {
            if let userInfo = notification.userInfo as? [String:Any],
               let isDefault = userInfo[NSApplication.launchIsDefaultUserInfoKey] as? Bool {
                if !isDefault {
                    DispatchQueue.main.async {
                        self.hide()
                    }
                }
            }
        } else if Defaults[.startFromLauncher] {
            Defaults[.startFromLauncher] = false
            
            DispatchQueue.main.async {
                self.hide()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        watcher.stopWatch()
    }
    
    private func registerNotification() {
        NotificationCenter.default.addObserver(forName: .simulatedWindowClose, object: nil, queue: nil) { _ in
            self.hide()
        }
        NotificationCenter.default.addObserver(forName: .updateWindow, object: nil, queue: nil) { notification in
            if let userInfo = notification.userInfo as? [String:NSWindow], let window = userInfo["window"] {
                self.window = window
            }
        }
        
        Defaults.observe(.autoLaunchWhenLogin) { change in
            self.setAutoStart()
        }.tieToLifetime(of: self)
    }
    
    private func setAutoStart() {
        #if !DEBUG
        let shouldEnable = Defaults[.autoLaunchWhenLogin]
        
        if #available(macOS 13.0, *) {
            do {
                if shouldEnable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print(error)
            }
            
        } else {
            if !SMLoginItemSetEnabled("com.parussoft.App-Helper-Launcher" as CFString, shouldEnable) {
                fatalError()
            }
        }
        #endif
    }
    
    private func setupMenubarTray() {
        let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        self.statusItem = statusItem
        
        guard let button = statusItem.button else {
            fatalError()
        }
        
        let image = NSImage(imageLiteralResourceName: "lion_menubar")
        button.image = image
        button.action = #selector(menuAction(_:))
    }
    
    @objc private func menuAction(_ sender:Any) {
        guard let window = self.window else {
            return
        }
        
        var operated = false
        window.center()
        
        if NSApp.isHidden {
            unhide()
            if !operated { operated = true }
        }
        
        if window.isMiniaturized {
            window.deminiaturize(nil)
            if !operated { operated = true }
        }
        
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            if !operated { operated = true }
        }
        
        guard window.isKeyWindow else { return }
        
        if !operated {
            hide()
        }
    }
    
    func hide() {
        removeFromDock()
        NSApp.hide(nil)
    }
    
    private func unhide() {
        showInDock()
        NSApp.unhide(nil)
    }
    
    private func showInDock() {
        NSApp.setActivationPolicy(.regular)
    }
    
    private func removeFromDock() {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct App_HelperApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var logProvider = LogProvider.shared
    
    @State private var currentTab:AHTab = .rules
    
    @State private var preventScreensaver = false
    @State private var assertionID: IOPMAssertionID = 0
    @State private var sleepDisabled = false
    
    var body: some Scene {
        WindowGroup {
            Group {
                switch currentTab {
                case .rules:
                    RulesView(preventScreensaver: $preventScreensaver,
                              assertionID: $assertionID,
                              sleepDisabled: $sleepDisabled)
                    .tabItem {
                        Label("Rules", systemImage: "ruler")
                    }
                case .logs:
                    LogView()
                        .tabItem {
                            Label("Logs", systemImage: "clock")
                        }
                }
            }
            .environment(\.managedObjectContext, logProvider.container.viewContext)
            .toolbar {
                ToolbarItemGroup {
                    Picker(selection: $currentTab) {
                        ForEach(AHTab.allCases) { tab in
                            Text(tab.localizedString).tag(tab)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    }
}

/*
 <a href="https://www.flaticon.com/free-icons/lion" title="lion icons">Lion icons created by justicon - Flaticon</a>
 <a href="https://www.flaticon.com/free-icons/lion" title="lion icons">Lion icons created by Freepik - Flaticon</a>
 */

enum AHTab:String, CaseIterable, Identifiable {
    case rules
    case logs
    
    var id: Self { self }
    
    var localizedString : String {
        switch self {
        case .rules:
            return NSLocalizedString("Rules", comment: "")
        case .logs:
            return NSLocalizedString("Logs", comment: "")
        }
    }
}
