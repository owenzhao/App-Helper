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
@MainActor
class BrewUpdateObserver: ObservableObject {
  static let shared = BrewUpdateObserver() // 转换为单例
  private var notificationCenter: NotificationCenter
  @Published var updateAppList: [String] = [] // 添加此属性
  @Published var isLoading: Bool = false // 添加加载状态
  @Published var showBrewHasNoUpdate: Bool = false // 添加无更新提示状态
  @Published var showBrewUpgradeAlert: Bool = false // 添加升级提示状态
  @Published var brewUpgradeResult: String? = nil // 添加升级结果

  // 修改计时器相关属性 - 简化为单一计时器
  private var minuteTimer: Timer?
  // 添加当前任务的取消令牌
  private var currentCheckTask: Task<Void, Never>?

  private init() {
    notificationCenter = NSWorkspace.shared.notificationCenter
    setupObservers()

    // 初始化时启动自动检查
    startAutoCheckIfEnabled()
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

    // 重启自动检查，确保系统休眠后继续正常工作
    startAutoCheckIfEnabled()
  }

  // 添加更新检查方法
  // First, create a custom global actor for background operations
  @globalActor actor BrewBackgroundActor {
    static let shared = BrewBackgroundActor()
    private init() {}
  }

  // Modified checkForUpdates function
  func checkForUpdates(background: Bool = false) async {
    // 如果是后台检查且自动更新已禁用，则直接返回
    if background && !Defaults[.enableBrewAutoUpdate] {
      return
    }

    // 取消之前的任务
    currentCheckTask?.cancel()

    let task = Task.detached {
      await MainActor.run {
        self.isLoading = true
      }

      defer {
        Task { @MainActor in
          self.isLoading = false
          Defaults[.lastBrewUpdateCheck] = Date()
        }
      }

      do {
        try await Task.sleep(nanoseconds: 1000)

        // 检查任务是否被取消
        if Task.isCancelled {
          return
        }

        // 在后台线程执行 brew 操作
        let updates = await Task.detached {
          BrewService.shared.checkBrewUpdate()
        }.value

        // 再次检查任务是否被取消
        if Task.isCancelled {
          return
        }

        await MainActor.run {
          self.updateUI(updates: updates)
          if updates.isEmpty && !background {
            self.showBrewHasNoUpdate = true
          }
        }
      } catch {
        if !Task.isCancelled {
          print("检查更新时发生错误: \(error)")
        }
      }
    }

    currentCheckTask = task
    await task.value
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
  func performUpgrade() async {
    await MainActor.run { isLoading = true }

    defer {
      Task { @MainActor in
        isLoading = false
      }
    }

    do {
      try await Task.sleep(nanoseconds: 1000)

      // 在后台线程执行 brew upgrade 操作
      let result = await Task.detached {
        BrewService.shared.upgradeBrew()
      }.value

      if result == NSLocalizedString("Operation timeout", comment: "Shell operation takes too long time.") {
        await MainActor.run {
          brewUpgradeResult = result
          showBrewUpgradeAlert = true
        }
      } else {
        await MainActor.run {
          brewUpgradeResult = result
          showBrewUpgradeAlert = true
          updateUI(updates: [])
        }
      }
    } catch {
      print("升级时发生错误: \(error)")

      await MainActor.run {
        brewUpgradeResult = error.localizedDescription
        showBrewUpgradeAlert = true
      }
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

  // 重写自动检查启动方法 - 统一使用分钟级检测
  private func startAutoCheckIfEnabled() {
    // 先停止已有的计时器
    stopAllTimers()

    // 只有在启用自动更新时才创建计时器
    guard Defaults[.enableBrewAutoUpdate] else { return }

    // 启动每分钟检测的计时器
    startMinuteTimer()
  }

  private func startMinuteTimer() {
    minuteTimer = Timer.scheduledTimer(
      withTimeInterval: 60, // 每分钟检测一次
      repeats: true
    ) { [weak self] _ in
      guard let self = self else { return }
      guard Defaults[.enableBrewAutoUpdate] else {
        Task { @MainActor in
          self.stopAllTimers()
        }
        return
      }

      // 检查是否需要执行更新 - 在主线程上执行
      Task { @MainActor in
        self.checkAndPerformUpdateIfNeeded()
      }
    }

    if let timer = minuteTimer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  // 新的核心检测方法
  private func checkAndPerformUpdateIfNeeded() {
    let frequency = Defaults[.brewUpdateFrequency]
    let lastUpdateDate = Defaults[.lastBrewUpdateCheck]

    if shouldPerformUpdateNow(lastUpdate: lastUpdateDate, frequency: frequency) {
      print("定时检测到需要执行更新：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))")

      Task {
        await checkForUpdates(background: true)
      }
    }
  }

  // 重构判断逻辑 - 基于当前时间点判断是否应该立即执行更新
  private func shouldPerformUpdateNow(lastUpdate: Date, frequency: BrewUpdateFrequency) -> Bool {
    let calendar = Calendar.current
    let now = Date()
    let scheduledTime = Defaults[.brewUpdateTime]
    let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)

    // 如果从未更新过，则需要更新
    if lastUpdate == Date.distantPast {
      return true
    }

    switch frequency {
    case .hourly:
      // 小时频率：如果距离上次更新超过1小时，则需要更新
      return now.timeIntervalSince(lastUpdate) >= 60 * 60

    case .daily:
      // 每日频率：检查今天是否应该更新且还没有更新
      let today = calendar.startOfDay(for: now)

      // 如果今天已经更新过了，不需要再更新
      if calendar.isDate(lastUpdate, inSameDayAs: now) {
        return false
      }

      // 构建今天的更新时间点
      var todayUpdateComponents = calendar.dateComponents([.year, .month, .day], from: today)
      todayUpdateComponents.hour = timeComponents.hour
      todayUpdateComponents.minute = timeComponents.minute
      todayUpdateComponents.second = 0

      guard let todayUpdateTime = calendar.date(from: todayUpdateComponents) else { return false }

      // 如果今天的更新时间已经过了，且今天还没更新过，则需要更新
      return now >= todayUpdateTime

    case .weekly:
      let selectedWeekday = Defaults[.brewUpdateWeekday]

      // 检查本周是否应该更新且还没有更新
      let thisWeekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
      let lastUpdateWeekInterval = calendar.dateInterval(of: .weekOfYear, for: lastUpdate)

      // 如果本周已经更新过了，不需要再更新
      if let thisWeek = thisWeekInterval, let lastWeek = lastUpdateWeekInterval,
         thisWeek.start == lastWeek.start {
        return false
      }

      // 构建本周的更新时间点
      var thisWeekUpdateComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
      thisWeekUpdateComponents.weekday = selectedWeekday.rawValue
      thisWeekUpdateComponents.hour = timeComponents.hour
      thisWeekUpdateComponents.minute = timeComponents.minute
      thisWeekUpdateComponents.second = 0

      guard let thisWeekUpdateTime = calendar.date(from: thisWeekUpdateComponents) else { return false }

      // 如果本周的更新时间已经过了，且本周还没更新过，则需要更新
      return now >= thisWeekUpdateTime
    }
  }

  // 添加停止所有计时器的方法
  private func stopAllTimers() {
    minuteTimer?.invalidate()
    minuteTimer = nil
  }

  // 添加公共方法来处理设置变化
  func handleAutoUpdateSettingChange() {
    if Defaults[.enableBrewAutoUpdate] {
      startAutoCheckIfEnabled()
    } else {
      stopAllTimers()
      // 取消当前正在进行的检查任务
      currentCheckTask?.cancel()
      currentCheckTask = nil

      // 如果当前正在加载，停止加载状态
      Task { @MainActor in
        if isLoading {
          isLoading = false
        }
      }
    }
  }

  // 添加处理频率变化的方法
  func handleFrequencyChange() {
    // 如果自动更新启用，重新启动检查
    if Defaults[.enableBrewAutoUpdate] {
      startAutoCheckIfEnabled()
    }
  }

  // 添加处理时间变化的方法
  func handleTimeChange() {
    // 如果自动更新启用且不是小时频率，重新启动检查
    if Defaults[.enableBrewAutoUpdate] && Defaults[.brewUpdateFrequency] != .hourly {
      startAutoCheckIfEnabled()
    }
  }

  deinit {
    notificationCenter.removeObserver(self)
    // 在对象释放时，由于使用了 [weak self]，Timer 回调会安全地提前返回
    // 当应用退出时，所有 Timer 都会被系统自动清理
    currentCheckTask?.cancel()
    currentCheckTask = nil
  }
}

struct BrewView: View {
  @StateObject private var observer = BrewUpdateObserver.shared

  var body: some View {
    BrewContentView(observer: observer)
      .onAppear {
        requestNotificationPermission()
        // 移除强制检测，让定时器根据时间规则自动判断
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
  @Default(.enableBrewAutoUpdate) private var isAutoUpdateEnabled
  @Default(.brewUpdateFrequency) private var updateFrequency
  @Default(.brewUpdateTime) private var updateTime
  @Default(.brewUpdateWeekday) private var updateWeekday

  @State private var showingSettings = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      brewToggleWithSettingsView

      if observer.updateAppList.isEmpty {
        // 合并的左侧内容区域
        combinedLeftContentView
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
        .frame(maxHeight: 800)
      }
    }
    .sheet(isPresented: $showingSettings) {
      BrewSettingsView(
        isAutoUpdateEnabled: $isAutoUpdateEnabled,
        updateFrequency: $updateFrequency,
        updateTime: $updateTime,
        updateWeekday: $updateWeekday,
        observer: observer
      )
    }
  }

  private var brewToggleWithSettingsView: some View {
    HStack {
      Toggle(isOn: $isAutoUpdateEnabled) {
        Text("Brew", comment: "Toggle for enabling automatic brew updates")
          .font(.title.bold())
      }
      .toggleStyle(SwitchToggleStyle())
      .onChange(of: isAutoUpdateEnabled) { _, newValue in
        observer.handleAutoUpdateSettingChange()
      }

      Spacer()

      Button(action: {
        showingSettings = true
      }) {
        Image(systemName: "gearshape")
          .font(.title2)
          .foregroundColor(.primary)
      }
      .buttonStyle(PlainButtonStyle())
      .disabled(!isAutoUpdateEnabled)
    }
  }

  private var checkUpdateButton: some View {
    Button("Check Update") {
      Task {
        await observer.checkForUpdates()
      }
    }
    .disabled(!isAutoUpdateEnabled)
  }

  private var upgradeButton: some View {
    Button("Upgrade") {
      Task {
        await observer.performUpgrade()
      }
    }
    .disabled(!isAutoUpdateEnabled)
  }

  @ViewBuilder
  private var lastUpdatedView: some View {
    if observer.isLoading {
      ProgressView()
        .controlSize(.small)
    } else {
      VStack {
        Text("Last Updated:", comment: "Label for last update time") +
        Text(Defaults[.lastBrewUpdateCheck], format: .dateTime.hour().minute().second())
      }
      .foregroundStyle(.green)
      .font(.subheadline)
    }
  }

  private var updateInfoView: some View {
    VStack(alignment: .leading) {
      HStack {
        upgradeButton
        lastUpdatedView
      }
      AppUpdateListView(apps: observer.updateAppList)
        .frame(height: 100)
        .overlay(alignment: .bottom) {
          Text("If the system prompts for App management (update or delete other applications) permission, please allow.", comment: "Permission prompt for app management")
            .font(.footnote)
            .foregroundStyle(.red)
        }
    }
  }

  // New view for the app update list
  private struct AppUpdateListView: View {
    let apps: [String]
    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(apps, id: \.self) { app in
            Text(app)
              .font(.body)
              .foregroundColor(.primary)
              .padding(.vertical, 2)
          }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(.secondary.opacity(0.2))
      .cornerRadius(12)
    }
  }

  private var combinedLeftContentView: some View {
    HStack(spacing: 8) {
      // 检查更新按钮
      checkUpdateButton

      // 最后更新时间
      if observer.isLoading {
        ProgressView()
          .controlSize(.small)
      } else {
        HStack {
          Text("Last Updated:", comment: "Label for last update time")
          Text(Defaults[.lastBrewUpdateCheck], format: .dateTime.hour().minute().second())
        }
        .foregroundStyle(.green)
        .font(.subheadline)
      }

      Spacer()

      // 简单的更新设置信息
      if isAutoUpdateEnabled {
        VStack(alignment: .trailing, spacing: 2) {
          Text("更新频率：\(updateFrequency.localizedTitle)", comment: "Update frequency display")
            .font(.subheadline)
            .foregroundColor(.primary)

          Text("下次更新时间：\(nextUpdateTimeString)", comment: "Next update time display")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
      }
    }
  }

  private var nextUpdateTimeString: String {
    let calendar = Calendar.current
    let now = Date()
    let scheduledTime = updateTime
    let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)

    switch updateFrequency {
    case .hourly:
      return NSLocalizedString("每小时", comment: "Next update time for hourly frequency")

    case .daily:
      var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
      todayComponents.hour = timeComponents.hour
      todayComponents.minute = timeComponents.minute
      todayComponents.second = 0

      guard let todayCheckTime = calendar.date(from: todayComponents) else {
        return NSLocalizedString("未知", comment: "Unknown next update time")
      }

      let nextUpdate = todayCheckTime > now ? todayCheckTime : calendar.date(byAdding: .day, value: 1, to: todayCheckTime) ?? todayCheckTime

      let formatter = DateFormatter()
      if calendar.isDateInToday(nextUpdate) {
        formatter.dateFormat = "HH:mm"
        return String(format: NSLocalizedString("今天%@", comment: "Next update today at specific time"), formatter.string(from: nextUpdate))
      } else if calendar.isDateInTomorrow(nextUpdate) {
        formatter.dateFormat = "HH:mm"
        return String(format: NSLocalizedString("明天%@", comment: "Next update tomorrow at specific time"), formatter.string(from: nextUpdate))
      } else {
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: nextUpdate)
      }

    case .weekly:
      var weekdayComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
      weekdayComponents.weekday = updateWeekday.rawValue
      weekdayComponents.hour = timeComponents.hour
      weekdayComponents.minute = timeComponents.minute
      weekdayComponents.second = 0

      guard let thisWeekDate = calendar.date(from: weekdayComponents) else {
        return NSLocalizedString("未知", comment: "Unknown next update time")
      }

      let nextUpdate = thisWeekDate > now ? thisWeekDate : calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeekDate) ?? thisWeekDate

      let formatter = DateFormatter()
      formatter.dateFormat = "EEEE MM月dd日 HH:mm"
      return formatter.string(from: nextUpdate)
    }
  }
}

// MARK: - Brew Settings View
struct BrewSettingsView: View {
  @Binding var isAutoUpdateEnabled: Bool
  @Binding var updateFrequency: BrewUpdateFrequency
  @Binding var updateTime: Date
  @Binding var updateWeekday: BrewUpdateWeekday
  let observer: BrewUpdateObserver

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // 主要设置内容区域
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            settingsHeaderView
            updateScheduleSection

            if updateFrequency == .daily {
              dailySettingsSection
            } else if updateFrequency == .weekly {
              weeklySettingsSection
            }

            if isAutoUpdateEnabled {
              nextUpdateSection
            }
          }
          .padding(.horizontal, 24)
          .padding(.top, 20)
        }

        Spacer()

        // 底部固定按钮
        bottomActionView
      }
      .navigationTitle("")
    }
    .frame(minWidth: 480, minHeight: 600)
  }

  private var settingsHeaderView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Brew Settings", comment: "Title for brew settings sheet")
        .font(.largeTitle.bold())
        .foregroundColor(.primary)

      Text("Configure automatic update schedule", comment: "Subtitle for brew settings")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
  }

  private var updateScheduleSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      sectionHeaderView(title: "Update Schedule", icon: "calendar")

      updateFrequencyPickerView
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
  }

  private var dailySettingsSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      sectionHeaderView(title: "Daily Settings", icon: "clock")

      VStack(spacing: 12) {
        settingRowView(
          label: "Update Time",
          icon: "clock.fill"
        ) {
          updateTimePickerView
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Color(.controlBackgroundColor))
      .cornerRadius(12)

      footerText("Updates will run daily at the specified time.")
    }
  }

  private var weeklySettingsSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      sectionHeaderView(title: "Weekly Settings", icon: "calendar.badge.clock")

      VStack(spacing: 12) {
        settingRowView(
          label: "Update Day",
          icon: "calendar"
        ) {
          weekdayPickerView
        }

        Divider()
          .padding(.horizontal, -4)

        settingRowView(
          label: "Update Time",
          icon: "clock.fill"
        ) {
          updateTimePickerView
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Color(.controlBackgroundColor))
      .cornerRadius(12)

      footerText("Updates will run weekly on the selected day at the specified time.")
    }
  }

  private var nextUpdateSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      sectionHeaderView(title: "Next Update", icon: "clock.badge")

      HStack(spacing: 12) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.title2)
          .foregroundColor(.blue)
          .frame(width: 24, height: 24)

        VStack(alignment: .leading, spacing: 4) {
          Text("Scheduled for", comment: "Label for next scheduled update")
            .font(.subheadline)
            .foregroundColor(.secondary)

          Text(nextUpdateTimeString)
            .font(.headline)
            .foregroundColor(.primary)
        }

        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .background(Color.blue.opacity(0.1))
      .cornerRadius(12)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.blue.opacity(0.3), lineWidth: 1)
      )
    }
  }

  private var bottomActionView: some View {
    VStack(spacing: 0) {
      Divider()

      HStack {
        Spacer()

        Button {
          dismiss()
        } label: {
          Text("Done", comment: "Done button in settings")
            .font(.headline)
            .foregroundColor(.white)
            .frame(minWidth: 80, minHeight: 36)
            .padding(.horizontal, 20)
            .background(Color.blue)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 16)
      .background(Color(.windowBackgroundColor))
    }
  }

  // MARK: - Helper Views

  private func sectionHeaderView(title: String, icon: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundColor(.blue)
        .frame(width: 20, height: 20)

      Text(LocalizedStringKey(title), comment: "Section header title")
        .font(.title3.bold())
        .foregroundColor(.primary)

      Spacer()
    }
  }

  private func settingRowView<Content: View>(
    label: String,
    icon: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: icon)
        .font(.body)
        .foregroundColor(.blue)
        .frame(width: 20, height: 20)

      Text(LocalizedStringKey(label), comment: "Setting row label")
        .font(.body.weight(.medium))
        .foregroundColor(.primary)
        .frame(minWidth: 100, alignment: .leading)

      Spacer()

      content()
    }
    .frame(minHeight: 44)
  }

  private func footerText(_ text: String) -> some View {
    Text(LocalizedStringKey(text), comment: "Footer explanation text")
      .font(.caption)
      .foregroundColor(.secondary)
      .padding(.horizontal, 4)
  }

  // MARK: - Setting Controls

  private var updateFrequencyPickerView: some View {
    Picker("Update Frequency", selection: $updateFrequency) {
      ForEach(BrewUpdateFrequency.allCases, id: \.self) { frequency in
        Text(frequency.localizedTitle)
          .tag(frequency)
      }
    }
    .pickerStyle(.segmented)
    .disabled(!isAutoUpdateEnabled)
    .onChange(of: updateFrequency) { _, newValue in
      observer.handleFrequencyChange()
    }
  }

  private var weekdayPickerView: some View {
    Picker("Update Day", selection: $updateWeekday) {
      ForEach(BrewUpdateWeekday.allCases, id: \.self) { weekday in
        Text(weekday.localizedTitle)
          .tag(weekday)
      }
    }
    .pickerStyle(.menu)
    .disabled(!isAutoUpdateEnabled)
    .onChange(of: updateWeekday) { _, newValue in
      observer.handleTimeChange()
    }
    .frame(minWidth: 120)
  }

  private var updateTimePickerView: some View {
    DatePicker(
      "Update Time",
      selection: $updateTime,
      displayedComponents: [.hourAndMinute]
    )
    .labelsHidden()
    .disabled(!isAutoUpdateEnabled)
    .onChange(of: updateTime) { _, newValue in
      observer.handleTimeChange()
    }
    .frame(minWidth: 120)
  }

  private var nextUpdateTimeString: String {
    let calendar = Calendar.current
    let now = Date()
    let scheduledTime = updateTime
    let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)

    switch updateFrequency {
    case .hourly:
      return NSLocalizedString("每小时", comment: "Next update time for hourly frequency")

    case .daily:
      var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
      todayComponents.hour = timeComponents.hour
      todayComponents.minute = timeComponents.minute
      todayComponents.second = 0

      guard let todayCheckTime = calendar.date(from: todayComponents) else {
        return NSLocalizedString("未知", comment: "Unknown next update time")
      }

      let nextUpdate = todayCheckTime > now ? todayCheckTime : calendar.date(byAdding: .day, value: 1, to: todayCheckTime) ?? todayCheckTime

      let formatter = DateFormatter()
      if calendar.isDateInToday(nextUpdate) {
        formatter.dateFormat = "HH:mm"
        return String(format: NSLocalizedString("今天%@", comment: "Next update today at specific time"), formatter.string(from: nextUpdate))
      } else if calendar.isDateInTomorrow(nextUpdate) {
        formatter.dateFormat = "HH:mm"
        return String(format: NSLocalizedString("明天%@", comment: "Next update tomorrow at specific time"), formatter.string(from: nextUpdate))
      } else {
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: nextUpdate)
      }

    case .weekly:
      var weekdayComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
      weekdayComponents.weekday = updateWeekday.rawValue
      weekdayComponents.hour = timeComponents.hour
      weekdayComponents.minute = timeComponents.minute
      weekdayComponents.second = 0

      guard let thisWeekDate = calendar.date(from: weekdayComponents) else {
        return NSLocalizedString("未知", comment: "Unknown next update time")
      }

      let nextUpdate = thisWeekDate > now ? thisWeekDate : calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeekDate) ?? thisWeekDate

      let formatter = DateFormatter()
      formatter.dateFormat = "EEEE MM月dd日 HH:mm"
      return formatter.string(from: nextUpdate)
    }
  }
}
