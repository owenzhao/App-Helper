//
//  GlobalShortcutManager.swift
//  App Helper
//
//  Created by zhaoxin on 2025/3/22.
//

import Cocoa
import ApplicationServices

class GlobalShortcutManager {
  private var eventMonitor: [Any]?
  private var registeredShortcut: String?

  private let specialKeyMap: [UInt16: String] = [
    116: "Page Up",
    121: "Page Down",
    117: "Del",
    114: "Insert",
    115: "Home",
    119: "End",
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

    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var currentShortcut = ""

    if modifiers.contains(.function) { currentShortcut += "Fn " }
    if modifiers.contains(.command) { currentShortcut += "⌘" }
    if modifiers.contains(.option) { currentShortcut += "⌥" }
    if modifiers.contains(.control) { currentShortcut += "⌃" }
    if modifiers.contains(.shift) { currentShortcut += "⇧" }

    if let specialKey = specialKeyMap[event.keyCode] {
      currentShortcut += specialKey
    } else if let key = event.characters?.uppercased() {
      if key == " " {
        currentShortcut += "Space"
      } else {
        currentShortcut += key
      }
    }

    if currentShortcut == registeredShortcut {
      putSystemToSleep()
    }

#if DEBUG
    print("Current shortcut: \(currentShortcut)")
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
