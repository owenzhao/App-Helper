//
//  KeyboardShortcutView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/3/22.
//

import SwiftUI
import Defaults

import SwiftUI
import Defaults

struct KeyboardShortcutView: View {
  @Binding var shortcut: String
  @Binding var isRecording: Bool
  var specialKeysEnabled: Bool = false
  @State private var tempShortcut: String = ""

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

  var body: some View {
    HStack {
      Button(action: {
        isRecording.toggle()
        if isRecording {
          tempShortcut = shortcut
        }
      }) {
        Text(isRecording ? tempShortcut.isEmpty ? "Recording..." : tempShortcut : shortcut.isEmpty ? "Click to record" : shortcut)
          .frame(minWidth: 100)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(isRecording ? Color.red.opacity(0.2) : Color.secondary.opacity(0.2))
          )
      }
      .buttonStyle(.plain)

      if isRecording {
        Button("Confirm") {
          shortcut = tempShortcut
          isRecording = false
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .onAppear {
      NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        guard isRecording else { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        var shortcutString = ""

        if modifiers.contains(.function) { shortcutString += "Fn " }
        if modifiers.contains(.command) { shortcutString += "⌘" }
        if modifiers.contains(.option) { shortcutString += "⌥" }
        if modifiers.contains(.control) { shortcutString += "⌃" }
        if modifiers.contains(.shift) { shortcutString += "⇧" }

        if let specialKey = specialKeyMap[keyCode] {
          shortcutString += specialKey
          tempShortcut = shortcutString
        } else if let key = event.characters?.uppercased() {
          shortcutString += key
          tempShortcut = shortcutString
        }

        return nil
      }
    }
  }
}

//#Preview {
//    KeyboardShortcutView()
//}
