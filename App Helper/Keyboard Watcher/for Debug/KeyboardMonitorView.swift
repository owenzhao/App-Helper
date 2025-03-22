//
//  KeyboardMonitorView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/3/22.
//

import SwiftUI

struct KeyboardMonitorView: View {
  @State private var pressedKeys: Set<String> = []

  private func keyString(from event: NSEvent) -> String {
    var keyString = ""

    // Check for modifiers
    if event.modifierFlags.contains(.control) { keyString += "⌃" }
    if event.modifierFlags.contains(.option) { keyString += "⌥" }
    if event.modifierFlags.contains(.shift) { keyString += "⇧" }
    if event.modifierFlags.contains(.command) { keyString += "⌘" }

    // Handle special keys
    let specialKey: String
    switch event.keyCode {
    case 126: specialKey = "↑"
    case 125: specialKey = "↓"
    case 124: specialKey = "→"
    case 123: specialKey = "←"
    case 53: specialKey = "⎋"  // Escape
    case 36: specialKey = "↩︎"  // Return
    case 76: specialKey = "↩︎"  // Numpad Return
    case 49: specialKey = "Space"
    case 51: specialKey = "⌫"  // Delete
    case 117: specialKey = "⌦"  // Forward Delete
    case 122: specialKey = "F1"
    case 120: specialKey = "F2"
    case 99: specialKey = "F3"
    case 118: specialKey = "F4"
    case 96: specialKey = "F5"
    case 97: specialKey = "F6"
    case 98: specialKey = "F7"
    case 100: specialKey = "F8"
    case 101: specialKey = "F9"
    case 109: specialKey = "F10"
    case 103: specialKey = "F11"
    case 111: specialKey = "F12"
    case 105: specialKey = "Fn"
    case 116: specialKey = "Page Up"
    case 121: specialKey = "Page Down"
    case 115: specialKey = "Home"
    case 119: specialKey = "End"
    default:
      if let characters = event.charactersIgnoringModifiers {
        specialKey = characters.uppercased()
      } else {
        specialKey = ""
      }
    }

    keyString += specialKey
    return keyString
  }

  var body: some View {
    Text(pressedKeys.isEmpty ? "No keys pressed" : pressedKeys.joined(separator: " + "))
      .padding()
      .font(.title)
      .onAppear {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
          let key = keyString(from: event)
          if event.type == .keyDown {
            pressedKeys.insert(key)
          } else if event.type == .keyUp {
            pressedKeys.remove(key)
          }
          return event
        }
      }
  }
}

#Preview {
  KeyboardMonitorView()
}
