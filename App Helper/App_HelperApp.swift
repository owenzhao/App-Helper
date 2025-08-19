//
//  App_HelperApp.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import AppKit
import Defaults
import ServiceManagement
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  private var statusItem: NSStatusItem?
  private var watcher = SystemWatcher.shared

  private var hasBrewUpdates = false
  private var timer: Timer?
  private var showBrewUpdates = false

  private let shortcutManager = GlobalShortcutManager()

  private var displaySectionWindow: NSWindow?
  private var popover: NSPopover? // Popover to host SwiftUI view for quick access

  func registerObserver() {
    shortcutManager.registerSleepShortcut(Defaults[.sleepShortcut]) // Command-Option-S
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    registerNotification()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMenubarTray()
    registerObserver()

    //    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
    //      NSApp.hide(nil)
    //    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    watcher.stopWatch()
  }

  func applicationWillHide(_ notification: Notification) {
    removeFromDock()
  }

  func applicationWillUnhide(_ notification: Notification) {
    showInDock()
  }

  private func registerNotification() {
    NotificationCenter.default.addObserver(forName: .simulatedWindowClose, object: nil, queue: nil) { _ in
      NSApp.hide(nil)
    }
    NotificationCenter.default.addObserver(forName: .updateWindow, object: nil, queue: nil) { notification in
      if let userInfo = notification.userInfo as? [String: NSWindow], let window = userInfo["window"] {
        self.window = window
      }
    }

    NotificationCenter.default.addObserver(forName: .hasBrewUpdates, object: nil, queue: nil) { notification in
      if let userInfo = notification.userInfo as? [String: Bool], let hasBrewUpdates = userInfo["hasBrewUpdates"] {
        self.hasBrewUpdates = hasBrewUpdates
        self.setupMenubarTray()
      }
    }

    Defaults.observe(.autoLaunchWhenLogin) { _ in
      self.setAutoStart()
    }.tieToLifetime(of: self)
  }

  private func setAutoStart() {
    #if !DEBUG
    let shouldEnable = Defaults[.autoLaunchWhenLogin]

    do {
      if shouldEnable {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      print(error)
    }
    #endif
  }

  private func invalidateTimerIfNeeded() {
    if timer != nil {
      timer?.invalidate()
      timer = nil
    }
  }

  private func showDisplaySectionWindow() {
    if displaySectionWindow == nil {
      let contentView = NSHostingView(rootView: RulesView.DisplaySectionView())
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
      window.contentView = contentView
      window.title = NSLocalizedString("Display Settings", comment: "Window title for display section")
      window.center()
      displaySectionWindow = window
    }
    displaySectionWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showMainAppWindow() {
    if window == nil {
      // Create and show main window if not initialized
      let mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                styleMask: [.titled, .closable, .resizable],
                                backing: .buffered, defer: false)
      mainWindow.contentView = NSHostingView(rootView: RulesView())
      mainWindow.title = NSLocalizedString("App Helper", comment: "Main app window title")
      mainWindow.center()
      window = mainWindow
    }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func setupMenubarTray() {
    invalidateTimerIfNeeded()

    if self.statusItem == nil {
      self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    }

    guard let button = self.statusItem?.button else {
      fatalError()
    }

    // Use a popover for rich menu content instead of NSMenu
    if popover == nil {
      let pop = NSPopover()
      pop.behavior = .transient // closes when focus changes
      pop.contentSize = NSSize(width: 360, height: 280)
      pop.contentViewController = NSHostingController(rootView: AppMenuPopoverView(openMainApp: { [weak self] in
        self?.showMainAppWindow()
      }))
      popover = pop
    }

    // Ensure no NSMenu is attached so clicks trigger the popover
    self.statusItem?.menu = nil

    // Left-click toggles the popover
    button.target = self
    button.action = #selector(togglePopover(_:))

    if hasBrewUpdates {
      self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
        guard let self else { return }
        self.showBrewUpdates.toggle()
        if self.showBrewUpdates {
          self.setMenuItemButtonTitle(button)
        } else {
          self.setMenuItemButtonImage(button)
        }
      })
    } else {
      setMenuItemButtonImage(button)
    }
  }

  @objc private func togglePopover(_ sender: Any?) {
    if let popover, popover.isShown {
      closePopover(sender)
    } else {
      showPopover(sender)
    }
  }

  private func showPopover(_ sender: Any?) {
    guard let button = statusItem?.button, let popover = popover else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func closePopover(_ sender: Any?) {
    popover?.performClose(sender)
  }

  private func setMenuItemButtonImage(_ button: NSStatusBarButton) {
    let image = NSImage(imageLiteralResourceName: "lion_menubar")
    button.image = image
    button.title = ""
  }

  private func setMenuItemButtonTitle(_ button: NSStatusBarButton) {
    button.image = nil
    button.title = "🍺"
  }

  @objc private func menuAction(_ sender: Any) {
    guard let window = window else {
      return
    }

    var operated = false
    window.center()

    if NSApp.isHidden {
      NSApp.unhide(nil)
      if !operated { operated = true }
    } else {
      print("not hidden")
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
      NSApp.hide(nil)
    }
  }

  private func showInDock() {
    NSApp.setActivationPolicy(.regular)
  }

  private func removeFromDock() {
    NSApp.setActivationPolicy(.accessory)
  }

  @objc private func handleDisplaySectionMenu() {
    showDisplaySectionWindow()
  }

  @objc private func handleMainAppMenu() {
    showMainAppWindow()
  }
}

@main
struct App_HelperApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
  @StateObject private var logProvider = LogProvider.shared

  @State private var currentTab: AHTab = .rules

  var body: some Scene {
    WindowGroup {
      Group {
        switch currentTab {
        case .rules:
          RulesView()
            .tabItem {
              Label("Rules", systemImage: "ruler")
            }
        case .logs:
          LogView()
            .tabItem {
              Label("Logs", systemImage: "clock")
            }
        case .xcode:
          XcodeView()
            .tabItem {
              Label("Xcode", systemImage: "hammer")
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

    //    WindowGroup {
    //      KeyboardMonitorView()
    //    }
  }
}

/*
 <a href="https://www.flaticon.com/free-icons/lion" title="lion icons">Lion icons created by justicon - Flaticon</a>
 <a href="https://www.flaticon.com/free-icons/lion" title="lion icons">Lion icons created by Freepik - Flaticon</a>
 */

enum AHTab: String, CaseIterable, Identifiable {
  case rules
  case logs
  case xcode

  var id: Self { self }

  var localizedString: String {
    switch self {
    case .rules:
      return NSLocalizedString("Rules", comment: "Rules tab title")
    case .logs:
      return NSLocalizedString("Logs", comment: "Logs tab title")
    case .xcode:
      return NSLocalizedString("Xcode", comment: "Xcode tab title")
    }
  }
}
