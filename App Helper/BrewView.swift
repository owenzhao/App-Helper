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

  // 添加自动检查计时器
  private var autoCheckTimer: Timer?

  private init() {
    notificationCenter = NSWorkspace.shared.notificationCenter
    setupObservers()

    // 初始化时启动自动检查计时器
    startAutoCheckTimer()
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
    print("Awake at: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))")

    // 重启自动检查计时器，确保系统休眠后继续正常工作
    startAutoCheckTimer()

    Task {
      await checkForUpdates(background: true)
    }
  }

  // 添加更新检查方法
  // First, create a custom global actor for background operations
  @globalActor actor BrewBackgroundActor {
    static let shared = BrewBackgroundActor()
    private init() {}
  }

  // Modified checkForUpdates function
  @BrewBackgroundActor
  func checkForUpdates(background: Bool = false) async {
    await MainActor.run { isLoading = true }

    defer {
      Task { @MainActor in
        isLoading = false
        Defaults[.lastBrewUpdateCheck] = Date()
      }
    }

    do {
      try await Task.sleep(nanoseconds: 1000)
      let updates = BrewService.shared.checkBrewUpdate()

      await MainActor.run {
        updateUI(updates: updates)
        if updates.isEmpty && !background {
          showBrewHasNoUpdate = true
        }
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

  // 添加升级方法
  @BrewBackgroundActor
  func performUpgrade() async {
    await MainActor.run { isLoading = true }

    defer {
      Task { @MainActor in
        isLoading = false
        updateUI(updates: [])
      }
    }

    do {
      try await Task.sleep(nanoseconds: 1000)
      let result = BrewService.shared.upgradeBrew()
      await MainActor.run {
        brewUpgradeResult = result
        showBrewUpgradeAlert = true
      }
    } catch {
      print("升级时发生错误: \(error)")
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

  // 添加启动自动检查计时器的方法
  private func startAutoCheckTimer() {
    // 先停止已有的计时器
    stopAutoCheckTimer()

    // 创建一个新的计时器，每60分钟执行一次
    autoCheckTimer = Timer.scheduledTimer(
      withTimeInterval: 60 * 60, // 60分钟
      repeats: true
    ) { [weak self] _ in
      guard let self = self else { return }
      print("自动检查Brew更新：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))")

      Task {
        await self.checkForUpdates(background: true)
      }
    }

    // 确保计时器在RunLoop中运行
    if let timer = autoCheckTimer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  // 添加停止计时器的方法
  private func stopAutoCheckTimer() {
    autoCheckTimer?.invalidate()
    autoCheckTimer = nil
  }

  deinit {
    notificationCenter.removeObserver(self)
    // 在对象释放时停止计时器
    stopAutoCheckTimer()
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
          await observer.checkForUpdates(background: true)
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
        lastUpdatedView
      } else {
        updateInfoView
      }
    }
    .alert("Brew has no updates.", isPresented: $observer.showBrewHasNoUpdate) {
    }
    .alert("Brew Upgrade", isPresented: $observer.showBrewUpgradeAlert) {
    } message: {
      if let result = observer.brewUpgradeResult {
        ScrollView {
          Text(result)
        }
      }
    }
  }

  private var updateInfoView: some View {
    VStack(alignment: .leading) {
      HStack {
        upgradeButton
        lastUpdatedView
      }

      List(observer.updateAppList, id: \.self) { app in
        Text(app)
      }
      .frame(height: 100) // 固定高度
      .overlay(alignment: .bottom, content: {
        Text("若系统弹出需要App管理（更新或删除其他应用程序）的权限，请允许。")
          .font(.footnote)
          .foregroundStyle(.red)
      })
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

  @ViewBuilder
  private var lastUpdatedView: some View {
    if observer.isLoading {
      ProgressView()
        .controlSize(.small)
    } else {
      VStack {
        Text("上次更新：") +
        Text(Defaults[.lastBrewUpdateCheck], format: .dateTime.hour().minute().second())
      }
      .foregroundStyle(.green)
      .font(.subheadline)
    }
  }
}

#Preview {
  BrewView()
}
