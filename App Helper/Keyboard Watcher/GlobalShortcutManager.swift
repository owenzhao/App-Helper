//
//  GlobalShortcutManager.swift
//  App Helper
//
//  Created by zhaoxin on 2025/3/22.
//

import Cocoa
import ApplicationServices

struct KeyboardShortcutFormatter {
  static let specialKeyMap: [UInt16: String] = [
    116: "Page Up",
    121: "Page Down",
    117: "Del",
    114: "Insert",
    115: "Home",
    119: "End",
    105: "Print Screen",
    107: "Scroll Lock",
    113: "Pause",
    122: "F1",
    120: "F2",
    99: "F3",
    118: "F4",
    96: "F5",
    97: "F6",
    98: "F7",
    100: "F8",
    101: "F9",
    109: "F10",
    103: "F11",
    111: "F12"
  ]

  static func modifierPrefix(from modifierFlags: NSEvent.ModifierFlags) -> String {
    var prefix = ""

    if modifierFlags.contains(.function) { prefix += "Fn " }
    if modifierFlags.contains(.command) { prefix += "⌘" }
    if modifierFlags.contains(.option) { prefix += "⌥" }
    if modifierFlags.contains(.control) { prefix += "⌃" }
    if modifierFlags.contains(.shift) { prefix += "⇧" }

    return prefix
  }

  static func keyStrings(for event: NSEvent) -> (key: String, legacy: String) {
    let legacy: String = {
      guard let key = event.characters?.uppercased() else { return "" }
      return (key == " ") ? "Space" : key
    }()

    if let specialKey = specialKeyMap[event.keyCode] {
      return (specialKey, legacy)
    }

    return (legacy, legacy)
  }

  static func shortcutStrings(for event: NSEvent) -> (current: String, legacy: String) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let prefix = modifierPrefix(from: modifiers)
    let keys = keyStrings(for: event)
    return (prefix + keys.key, prefix + keys.legacy)
  }
}

class GlobalShortcutManager {
  private var eventMonitor: [Any]?
  private var registeredShortcut: String?

  init() {
    startMonitoring()
  }

  deinit {
    stopMonitoring()
  }

  func registerSleepShortcut(_ shortcutString: String) {
    registeredShortcut = shortcutString.isEmpty ? nil : shortcutString
  }

  /// Enable or disable global/local key monitoring at runtime.
  func setEnabled(_ enabled: Bool) {
    if enabled {
      if eventMonitor == nil {
        startMonitoring()
      }
    } else {
      if eventMonitor != nil {
        stopMonitoring()
      }
    }
  }

  private func startMonitoring() {
    // Check accessibility permissions
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

    guard accessibilityEnabled else {
      print("Accessibility permissions not granted")
      return
    }

    // Global monitor for background events
    let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleKeyEvent(event)
    }

    // Local monitor for foreground events
    let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleKeyEvent(event)
      return event
    }

    if let globalMonitor = globalMonitor, let localMonitor = localMonitor {
      eventMonitor = [globalMonitor, localMonitor]
    }
  }

  // Helper method to handle key events
  private func handleKeyEvent(_ event: NSEvent) {
    guard let registeredShortcut = self.registeredShortcut else { return }

    let shortcutStrings = KeyboardShortcutFormatter.shortcutStrings(for: event)
    if shortcutStrings.current == registeredShortcut || shortcutStrings.legacy == registeredShortcut {
      putSystemToSleep()
    }

#if DEBUG
    print("Current shortcut: \(shortcutStrings.current)")
#endif
  }

  private func stopMonitoring() {
    if let monitors = eventMonitor {
      monitors.forEach { NSEvent.removeMonitor($0) }
    }
    eventMonitor = nil
  }

  private func putSystemToSleep() {
    // 先测试并请求 Automation 权限
    if !checkAutomationPermission() {
      // 权限检查失败，checkAutomationPermission 会弹出系统对话框
      return
    }

    // 权限已授予，执行睡眠
    let script = """
        tell application "System Events" to sleep
        """

    if let appleScript = NSAppleScript(source: script) {
      var error: NSDictionary?
      appleScript.executeAndReturnError(&error)

      if let error = error {
        print("Error executing sleep command: \(error)")
      }
    }
  }

  /// 检查 Automation 权限，如果未授予则弹出系统对话框请求
  /// 返回 true 表示已授权，false 表示未授权或用户拒绝
  private func checkAutomationPermission() -> Bool {
    // 先用一个小测试来触发权限检查
    let testScript = """
        tell application "System Events" to return name
        """

    guard let appleScript = NSAppleScript(source: testScript) else {
      return false
    }

    var error: NSDictionary?
    appleScript.executeAndReturnError(&error)

    if let error = error {
      let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0

      // -1743 表示没有 Automation 权限
      if errorNumber == -1743 {
        // 尝试通过打开系统设置来让用户手动授权
        DispatchQueue.main.async {
          NSApp.activate(ignoringOtherApps: true)

          let alert = NSAlert()
          alert.messageText = "Permission Required"
          alert.informativeText = "App Helper needs Automation permission to put your Mac to sleep.\n\nClick 'Open System Settings' and enable App Helper in the Automation section."
          alert.alertStyle = .warning
          alert.addButton(withTitle: "Open System Settings")
          alert.addButton(withTitle: "Cancel")

          let response = alert.runModal()

          if response == .alertFirstButtonReturn {
            self.openAutomationSettings()
          }
        }
        return false
      }

      print("Automation permission test failed: \(error)")
      return false
    }

    return true
  }

  /// 打开系统偏好设置的自动化权限页面
  private func openAutomationSettings() {
    // 打开自动化设置页面
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
      NSWorkspace.shared.open(url)
    }
  }
}
