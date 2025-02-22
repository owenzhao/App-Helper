//
//  BrewView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/2/8.
//

import Defaults
import SwiftUI
import UserNotifications

// 创建一个 ObservableObject 来处理系统通知
class BrewUpdateObserver: ObservableObject {
  static let shared = BrewUpdateObserver() // 转换为单例
  private var notificationCenter: NotificationCenter
  @Published var updateAppList: [String] = [] // 添加此属性
  @Published var isLoading: Bool = false // 添加加载状态
  @Published var showBrewHasNoUpdate: Bool = false // 添加无更新提示状态
  @Published var showBrewUpgradeAlert: Bool = false // 添加升级提示状态
  @Published var brewUpgradeResult: String? = nil // 添加升级结果

  private init() {
    notificationCenter = NSWorkspace.shared.notificationCenter
    setupObservers()
  }

  private func setupObservers() {
    // 监听系统唤醒
    notificationCenter.addObserver(
      self,
      selector: #selector(handleSystemWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )

    // 监听应用程序启动完成
    notificationCenter.addObserver(
      self,
      selector: #selector(handleSystemWake),
      name: NSApplication.didFinishLaunchingNotification,
      object: nil
    )
  }

  @objc private func handleSystemWake() {
    checkIfNeedUpdate(background: true)
  }

  // 根据brew的设置，时长超过60分钟则在调用outdated的时候会自动先调用update。
  func checkIfNeedUpdate(background: Bool = false) {
    let lastCheckDate = Defaults[.lastBrewUpdateCheck]

    if Date().timeIntervalSince(lastCheckDate) > 60 * 60 { // 大于1小时
      Task {
        await checkForUpdates(background: background)
      }
    }
  }

  // 添加更新检查方法
  @MainActor
  func checkForUpdates(background: Bool = false) async {
    isLoading = true

    defer {
      isLoading = false
      Defaults[.lastBrewUpdateCheck] = Date()
    }

    do {
      if !background {
        try await Task.sleep(nanoseconds: 1000) // 为动画效果
      }

      let updates = BrewService.shared.checkBrewUpdate()

      defer {
        updateUI(updates: updates)
      }

      if updates.isEmpty && !background {
        showBrewHasNoUpdate = true
      }
    } catch {
      print("检查更新时发生错误: \(error)")
    }
  }

  private func updateUI(updates: [String]) {
    self.updateAppList = updates

    if updateAppList.isEmpty {
      NotificationCenter.default.post(name: .hasBrewUpdates, object: nil, userInfo: ["hasBrewUpdates": false])
    } else {
      NotificationCenter.default.post(name: .hasBrewUpdates, object: nil, userInfo: ["hasBrewUpdates": true])
      sendUpdateNotification(packages: updates)
    }
  }

  private func sendUpdateNotification(packages: [String]) {
    let content = UNMutableNotificationContent()
    content.title = "Homebrew更新可用"
    content.body = "发现\(packages.count)个包需要更新：\(packages.joined(separator: ", "))"
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("发送通知失败: \(error.localizedDescription)")
      }
    }
  }

  // 添加升级方法
  @MainActor
  func performUpgrade() async {
    isLoading = true
    defer {
      isLoading = false
      updateUI(updates: [])
    }

    do {
      try await Task.sleep(nanoseconds: 1000)
      brewUpgradeResult = BrewService.shared.upgradeBrew()
      showBrewUpgradeAlert = true
    } catch {
      print("升级时发生错误: \(error)")
    }
  }

  deinit {
    notificationCenter.removeObserver(self)
  }
}

struct BrewView: View {
  @StateObject private var observer = BrewUpdateObserver.shared

  var body: some View {
    BrewContentView(observer: observer)
      .onAppear {
        requestNotificationPermission()

        Task {
          try await Task.sleep(nanoseconds: 1000000000 * 3)
          observer.checkIfNeedUpdate(background: true)
        }
      }
  }

  private func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
      if granted {
        print("通知权限已获取")
      } else if let error = error {
        print("请求通知权限失败: \(error.localizedDescription)")
      }
    }
  }
}

// 将视图逻辑分离到子视图中
private struct BrewContentView: View {
  @ObservedObject var observer: BrewUpdateObserver

  var body: some View {
    HStack {
      if observer.updateAppList.isEmpty {
        checkUpdateButton
      } else {
        updateInfoView
      }

      if observer.isLoading {
        ProgressView()
          .controlSize(.small)
      } else {
        TimelineView(.periodic(from: Date(), by: 30)) { _ in
          Text(Defaults[.lastBrewUpdateCheck], format: .relative(presentation: .named))
            .foregroundStyle(.green)
            .font(.subheadline)
        }
      }
    }
    .alert("Brew has no updates.", isPresented: $observer.showBrewHasNoUpdate) {
    }
    .alert("Brew Upgrade", isPresented: $observer.showBrewUpgradeAlert) {
    } message: {
      if let result = observer.brewUpgradeResult {
        Text(result)
      }
    }
  }

  private var updateInfoView: some View {
    VStack(alignment: .leading) {
      upgradeButton

      List(observer.updateAppList, id: \.self) { app in
        Text(app)
      }
      .cornerRadius(12)
    }
  }

  private var checkUpdateButton: some View {
    Button("Check Update") {
      Task {
        await observer.checkForUpdates()
      }
    }
  }

  private var upgradeButton: some View {
    Button("Upgrade") {
      Task {
        await observer.performUpgrade()
      }
    }
  }
}

#Preview {
  BrewView()
}
