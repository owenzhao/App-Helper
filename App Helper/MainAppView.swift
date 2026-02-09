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
      ToolbarItemGroup {
        AHTabPicker(selection: $currentTab)
      }
    }
    .navigationTitle(Text("App Helper", comment: "Main window title"))
  }
}
