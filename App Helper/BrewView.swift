//
//  BrewView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/2/8.
//

import SwiftUI
import UserNotifications
import Defaults

// 创建一个 ObservableObject 来处理系统通知
class BrewUpdateObserver: ObservableObject {
  private var notificationCenter: NotificationCenter
  @Published var updateAppList: [String] = [] // 添加此属性
  @Published var isLoading: Bool = false // 添加加载状态
  @Published var showBrewHasNoUpdate: Bool = false // 添加无更新提示状态
  @Published var showBrewUpgradeAlert: Bool = false // 添加升级提示状态
  @Published var brewUpgradeResult: String? = nil // 添加升级结果

  init() {
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
  }

  @objc private func handleSystemWake() {
    checkIfNeedUpdate()
  }

  func checkIfNeedUpdate() {
    let lastCheckDate = Defaults[.lastBrewUpdateCheck]

    // 检查是否是同一天
    let calendar = Calendar.current
    if !calendar.isDate(lastCheckDate, inSameDayAs: Date()) {
      Task {
        await checkForUpdates()
        Defaults[.lastBrewUpdateCheck] = Date()
      }
    } else {
      Task {
        await setBrewOutdated()
      }
    }
  }

  // 添加更新检查方法
  @MainActor
  func checkForUpdates() async {
    isLoading = true
    defer { isLoading = false }

    do {
      try await Task.sleep(nanoseconds: 1000) // 为动画效果
      let updates = BrewManager.shared.checkBrewUpdate()

      if updates.isEmpty {
        showBrewHasNoUpdate = true
        updateAppList = []
      } else {
        updateAppList = updates
        sendUpdateNotification(packages: updates)
      }
    } catch {
    }
  }

  @MainActor
  func setBrewOutdated() async {
    isLoading = true
    defer { isLoading = false }

    do {
      try await Task.sleep(nanoseconds: 1000) // 为动画效果
      let updates = BrewManager.shared.getBrewOutdated()

      if !updates.isEmpty {
        updateAppList = updates
        sendUpdateNotification(packages: updates)
      }
    } catch {
    }
  }

  private func sendUpdateNotification(packages: [String]) {
    let content = UNMutableNotificationContent()
    content.title = "Homebrew更新可用"
    content.body = "发现\(packages.count)个包需要更新：\(packages.joined(separator: ", "))"
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: trigger
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
      updateAppList = []
    }

    do {
      try await Task.sleep(nanoseconds: 1000)
      brewUpgradeResult = BrewManager.shared.upgradeBrew()
      showBrewUpgradeAlert = true
    } catch {
      print("升级时发生错误: \(error)")
    }
  }

  deinit {
    notificationCenter.removeObserver(self)
  }
}

// 创建一个单例来管理 Brew 操作
class BrewManager {
  static let shared = BrewManager()

  private init() {}

  func updateBrew() {
    shell("/opt/homebrew/bin/brew update")
  }

  func checkBrewUpdate() -> [String] {
    updateBrew()
    return getBrewOutdated()
  }

  func getBrewOutdated() -> [String] {
    let output = shell("/opt/homebrew/bin/brew outdated")
    return output.split(separator: "\n").map(String.init)
  }

  func upgradeBrew() -> String {
    return shell("/opt/homebrew/bin/brew upgrade")
  }
}

struct BrewView: View {
  @StateObject private var observer = BrewUpdateObserver()

  var body: some View {
    HStack {
      if observer.updateAppList.isEmpty {
        checkUpdateButton
      } else {
        VStack(alignment: .leading) {
          upgradeButton

          List(observer.updateAppList, id: \.self) { app in
            Text(app)
          }
          .cornerRadius(12)
        }
      }

      if observer.isLoading {
        ProgressView()
          .controlSize(.small)
      } else {
        Text(Defaults[.lastBrewUpdateCheck], format: .relative(presentation: .named))
          .foregroundStyle(.green)
          .font(.subheadline)
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
    .onAppear {
      requestNotificationPermission()
      observer.checkIfNeedUpdate()
    }
  }

  // 请求通知权限
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

extension BrewView {
  var checkUpdateButton: some View {
    Button("Check Update") {
      Task {
        await observer.checkForUpdates()
      }
    }
  }

  var upgradeButton: some View {
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
