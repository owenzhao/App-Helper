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
  private var statusMenu: NSMenu? // retain the menu
  private var observationTasks: [Task<Void, Never>] = []

  func registerObserver() {
    // Register current values at launch
    shortcutManager.registerSleepShortcut(Defaults[.sleepShortcut])
    shortcutManager.setEnabled(Defaults[.enableSleepWatching])

    // Start per-key observation tasks using the new Defaults.updates API
    startObservationTasks()
  }

  private func startObservationTasks() {
    // Cancel any existing tasks first to avoid duplication
    cancelObservationTasks()

    // Sleep shortcut updates
    let sleepTask = Task { [weak self] in
      guard let self else { return }
      for await change in Defaults.updates(.sleepShortcut, initial: false) {
        await MainActor.run {
          self.shortcutManager.registerSleepShortcut(change)
        }
      }
    }

    // Enable sleep watching updates
    let enableTask = Task { [weak self] in
      guard let self else { return }
      for await change in Defaults.updates(.enableSleepWatching, initial: false) {
        await MainActor.run {
          self.shortcutManager.setEnabled(change)
        }
      }
    }

    // Auto start preference updates
    let autoStartTask = Task { [weak self] in
      guard let self else { return }
      for await _ in Defaults.updates(.autoLaunchWhenLogin, initial: false) {
        await MainActor.run {
          self.setAutoStart()
        }
      }
    }

    observationTasks.append(contentsOf: [sleepTask, enableTask, autoStartTask])
  }

  private func cancelObservationTasks() {
    for task in observationTasks {
      task.cancel()
    }
    observationTasks.removeAll()
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    registerNotification()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMenubarTray()
    registerObserver()
    showMainAppWindow()
    replaceDockerIcon()

    //    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
    //      NSApp.hide(nil)
    //    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    watcher.stopWatch()
    cancelObservationTasks()
  }

  private func registerNotification() {
    NotificationCenter.default.addObserver(forName: .simulatedWindowClose, object: nil, queue: nil) { _ in
      NSApp.hide(nil)
      NSApp.setActivationPolicy(.accessory) // Hide Dock icon when main window is closed
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

  private func showMainAppWindow() {
    NSApp.setActivationPolicy(.regular) // Show Dock icon when main window is shown
    if window == nil {
      // Create and show main window if not initialized
      let mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                styleMask: [.titled, .closable, .resizable],
                                backing: .buffered, defer: false)
      mainWindow.contentView = NSHostingView(rootView: MainAppView())
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

    // Build and assign a native NSMenu for the status item
    let menu = buildStatusMenu()
    self.statusMenu = menu
    self.statusItem?.menu = menu

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

  private func replaceDockerIcon() {

    // Attempt to load the custom Dock icon from asset catalog
    if let icon = NSImage(named: "app_icon_256") {
      NSApplication.shared.applicationIconImage = icon
    }
  }

  // MARK: - Status Menu Builder
  private func buildStatusMenu() -> NSMenu {
    let menu = NSMenu()

    // Display section
    let displayTitle = NSLocalizedString("Display", comment: "Display section title in status menu")
    let displayHeader = NSMenuItem(title: displayTitle, action: nil, keyEquivalent: "")
    displayHeader.isEnabled = false
    menu.addItem(displayHeader)

    let appearanceTitle = NSLocalizedString("Toggle System Color Theme", comment: "Menu item to toggle system appearance")
    let appearanceItem = NSMenuItem(title: appearanceTitle, action: #selector(toggleAppearanceMenuAction(_:)), keyEquivalent: "")
    appearanceItem.target = self
    menu.addItem(appearanceItem)

    menu.addItem(.separator())

    // Open main app
    let openMainTitle = NSLocalizedString("Open Main App", comment: "Menu item to open the main application window")
    let openMainItem = NSMenuItem(title: openMainTitle, action: #selector(openMainAppMenuAction(_:)), keyEquivalent: "")
    openMainItem.target = self
    menu.addItem(openMainItem)

    return menu
  }

  // MARK: - Menu Actions
  @objc private func toggleAppearanceMenuAction(_ sender: Any?) {
    RulesView.toggleSystemAppearance()
  }

  @objc private func openMainAppMenuAction(_ sender: Any?) {
    showMainAppWindow()
  }

  private func setMenuItemButtonImage(_ button: NSStatusBarButton) {
    let image = NSImage(imageLiteralResourceName: getMenuItemImageName())
    button.image = image
    button.title = ""
  }

  private func getMenuItemImageName() -> String {
#if DEBUG
    return "lion_menubar_beta"
#else
    return "lion_menubar"
#endif
  }

  private func setMenuItemButtonTitle(_ button: NSStatusBarButton) {
    button.image = nil
    button.title = "🍺"
  }
}

@main
struct App_HelperApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  var body: some Scene {
    WindowGroup {
      MainAppView()
    }
//    .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    .commands {
      CommandGroup(replacing: .newItem) {
        // 留空，这样就移除了新建相关的菜单项
      }
    }
    //    WindowGroup {
    //      KeyboardMonitorView()
    //    }
  }
}

// MARK: - Style utilities
private enum AHStyle {
  private static func accentNSColor() -> NSColor {
    if let c = NSColor(named: "AccentColor"), c.alphaComponent > 0.05 {
      return c
    }
    return NSColor.controlAccentColor
  }

  static func selectedBackground() -> Color {
    Color(nsColor: accentNSColor())
  }

  static func selectedForeground(for scheme: ColorScheme) -> Color {
    switch scheme {
    case .dark:
      return Color.white
    default:
      return Color.black
    }
  }

  static var segmentStroke: Color { Color.secondary.opacity(0.25) }
}

// MARK: - Views
struct AHTabPicker: View {
  @Binding var selection: AHTab
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 4) {
      ForEach(AHTab.allCases) { tab in
        segment(for: tab)
      }
    }
    .padding(2)
    .background(
      Capsule()
        .strokeBorder(AHStyle.segmentStroke, lineWidth: 1)
    )
  }
}

private extension AHTabPicker {
  @ViewBuilder
  func segment(for tab: AHTab) -> some View {
    let isSelected = (tab == selection)

    Button {
      selection = tab
    } label: {
      HStack(spacing: 6) {
        tab.iconView
        Text(tab.localizedString)
          .lineLimit(1)
      }
      .padding(.vertical, 4)
      .padding(.horizontal, 10)
      .frame(minHeight: 22)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .background(
      Capsule()
        .fill(isSelected ? AHStyle.selectedBackground() : Color.clear)
    )
    .foregroundStyle(isSelected ? AHStyle.selectedForeground(for: colorScheme) : Color.primary)
    .accessibilityLabel(Text(tab.localizedString))
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

// Icon helpers for AHTab
extension AHTab {
  @ViewBuilder
  var iconView: some View {
    if NSImage(systemSymbolName: sfSymbolName, accessibilityDescription: nil) != nil {
      Image(systemName: sfSymbolName)
        .imageScale(.medium)
        .help(localizedString)
    } else {
      Text(emoji)
        .font(.system(size: 13))
        .help(localizedString)
    }
  }

  private var emoji: String {
    switch self {
    case .rules: return "📐"
    case .logs: return "🕒"
    case .xcode: return "🔨"
    case .codeCleaner: return "✨"
    }
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
  case codeCleaner

  var id: Self { self }

  var localizedString: String {
    switch self {
    case .rules:
      return NSLocalizedString("Rules", comment: "Rules tab title")
    case .logs:
      return NSLocalizedString("Logs", comment: "Logs tab title")
    case .xcode:
      return NSLocalizedString("Xcode", comment: "Xcode tab title")
    case .codeCleaner:
      return NSLocalizedString("Code Cleaner", comment: "Code Cleaner tab title")
    }
  }

  var sfSymbolName: String {
    switch self {
    case .rules:
      return "ruler"
    case .logs:
      return "clock"
    case .xcode:
      return "hammer"
    case .codeCleaner:
      return "wand.and.stars"
    }
  }
}
