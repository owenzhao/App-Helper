//
//  KeyboardShortcutView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/3/22.
//

import SwiftUI
import Defaults

struct KeyboardShortcutView: View {
  @Binding var shortcut: String
  @Binding var isRecording: Bool
  var specialKeysEnabled: Bool = false
  @State private var tempShortcut: String = ""

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

        let shortcutStrings = KeyboardShortcutFormatter.shortcutStrings(for: event)
        guard !shortcutStrings.current.isEmpty else { return nil }
        tempShortcut = shortcutStrings.current

        return nil
      }
    }
  }
}

//#Preview {
//    KeyboardShortcutView()
//}
