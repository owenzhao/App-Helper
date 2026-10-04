// MainAppView.swift
// 主界面显示在菜单栏弹出面板中。
import SwiftUI

struct MainAppView: View {
  @StateObject private var logProvider = LogProvider.shared
  @State private var currentTab: AHTab = .rules

  let onCheckForUpdates: () -> Void
  let onQuit: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("App Helper")
            .font(.headline)
          if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            Text(version)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Picker(selection: $currentTab) {
          ForEach(AHTab.allCases) { tab in
            Text(tab.localizedString).tag(tab)
          }
        } label: {
          EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      Group {
        switch currentTab {
        case .rules:
          RulesView()
        case .logs:
          LogView()
            .environment(\.managedObjectContext, logProvider.container.viewContext)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      HStack {
        Button(action: RulesView.toggleSystemAppearance) {
          Image(systemName: "circle.lefthalf.filled")
        }
        .help(NSLocalizedString("Toggle System Color Theme", comment: "Menu item to toggle system appearance"))

        Spacer()

        Button("Check for Updates…", action: onCheckForUpdates)
        Button("Quit", action: onQuit)
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .frame(width: 560, height: 700)
  }
}
