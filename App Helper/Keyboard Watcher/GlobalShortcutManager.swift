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
}
