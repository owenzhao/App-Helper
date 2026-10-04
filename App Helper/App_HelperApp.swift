//
//  App_HelperApp.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import AppKit
import Defaults
import ServiceManagement
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private var watcher = SystemWatcher.shared

  private var hasBrewUpdates = false
  private var timer: Timer?
  private var showBrewUpdates = false

  private let shortcutManager = GlobalShortcutManager()
  private var observationTasks: [Task<Void, Never>] = []
  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

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
    NSApp.setActivationPolicy(.accessory)
    setupMenubarTray()
    registerObserver()
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 560, height: 700)
    popover.contentViewController = NSHostingController(
      rootView: MainAppView(
        onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
        onQuit: { NSApp.terminate(nil) }
      )
    )
  }

  func applicationWillTerminate(_ notification: Notification) {
    watcher.stopWatch()
    cancelObservationTasks()
  }

  private func registerNotification() {
    NotificationCenter.default.addObserver(forName: .hasBrewUpdates, object: nil, queue: nil) { notification in
      if let userInfo = notification.userInfo as? [String: Bool], let hasBrewUpdates = userInfo["hasBrewUpdates"] {
        self.hasBrewUpdates = hasBrewUpdates
        self.setupMenubarTray()
      }
    }

    // HDR状态变化时更新菜单栏图标
    NotificationCenter.default.addObserver(forName: .ahHDRDisplayDidChange, object: nil, queue: nil) { [weak self] _ in
      self?.updateMenubarIconForHDR()
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

  private func setupMenubarTray() {
    invalidateTimerIfNeeded()

    if self.statusItem == nil {
      self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    guard let button = self.statusItem?.button else {
      fatalError()
    }

    // 设置按钮宽度以容纳文本
    button.controlSize = .regular

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
      // 检查HDR状态并更新图标
      updateMenubarIconForHDR()
    }
  }

  @objc private func togglePopover(_ sender: Any?) {
    guard let button = statusItem?.button else { return }
    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  func checkForUpdates() {
    updaterController.checkForUpdates(nil)
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

  // 根据HDR状态更新菜单栏图标
  private func updateMenubarIconForHDR() {
    guard let button = statusItem?.button else { return }

    // 如果有brew更新显示，暂时跳过
    if hasBrewUpdates { return }

    let isHDROn = checkHDRStatus()
    if isHDROn {
      button.image = nil
      button.title = "HDR"
    } else {
      button.title = ""
      let image = NSImage(imageLiteralResourceName: getMenuItemImageName())
      button.image = image
    }
  }

  // 检测HDR状态（使用与RulesView相同的私有API）
  private func checkHDRStatus() -> Bool {
    typealias HDRBoolFunction = @convention(c) (CGDirectDisplayID) -> Bool

    let skyLightHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    guard let slsSupportsHDRMode = skyLightHandle.flatMap({ dlsym($0, "SLSDisplaySupportsHDRMode") }),
          let slsIsHDRModeEnabled = skyLightHandle.flatMap({ dlsym($0, "SLSDisplayIsHDRModeEnabled") }) else {
      return false
    }

    let supportsHDR = unsafeBitCast(slsSupportsHDRMode, to: HDRBoolFunction.self)
    let isHDREnabled = unsafeBitCast(slsIsHDRModeEnabled, to: HDRBoolFunction.self)

    guard let screen = NSScreen.main ?? NSScreen.screens.first,
          let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
      return false
    }

    let displayID = CGDirectDisplayID(screenNumber.uint32Value)

    if supportsHDR(displayID) == false {
      return false
    }

    return isHDREnabled(displayID)
  }
}

@main
struct App_HelperApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(after: .appInfo) {
        Button(NSLocalizedString("Check for Updates…", comment: "Check for updates menu item")) {
          appDelegate.checkForUpdates()
        }
      }
      CommandGroup(replacing: .newItem) {
        // 留空，这样就移除了新建相关的菜单项
      }
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

  var id: Self { self }

  var localizedString: String {
    switch self {
    case .rules:
      return NSLocalizedString("Rules", comment: "Rules tab title")
    case .logs:
      return NSLocalizedString("Logs", comment: "Logs tab title")
    }
  }
}
