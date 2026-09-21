// MainAppView.swift
// 封装主视图，供 App_HelperApp 和 AppDelegate 复用
import SwiftUI

struct MainAppView: View {
  @StateObject private var logProvider = LogProvider.shared
  @State private var currentTab: AHTab = .rules

  var body: some View {
    Group {
      switch currentTab {
      case .rules:
        RulesView()
      case .logs:
        LogView()
          .environment(\.managedObjectContext, logProvider.container.viewContext)
      }
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker(selection: $currentTab) {
          ForEach(AHTab.allCases) { tab in
            // `.segmented` renders a `Label` as icon-only on macOS; use the
            // localized title so the two tabs stay unambiguous.
            Text(tab.localizedString)
              .tag(tab)
          }
        } label: {
          EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .layoutPriority(1)
      }
    }
  }
}
