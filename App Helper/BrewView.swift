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

  // 修改计时器相关属性
  private var autoCheckTimer: Timer?
  private var scheduledCheckTimer: Timer?
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

    if Defaults[.enableBrewAutoUpdate] {
      Task {
        await checkForUpdates(background: true)
      }
    }
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

  // 重写自动检查启动方法
  private func startAutoCheckIfEnabled() {
    // 先停止已有的计时器
    stopAllTimers()

    // 只有在启用自动更新时才创建计时器
    guard Defaults[.enableBrewAutoUpdate] else { return }

    let frequency = Defaults[.brewUpdateFrequency]

    switch frequency {
    case .hourly:
      startHourlyTimer()
    case .daily:
      startDailyTimer()
    case .weekly:
      startWeeklyTimer()
    }
  }

  private func startHourlyTimer() {
    autoCheckTimer = Timer.scheduledTimer(
      withTimeInterval: 60 * 60, // 60分钟
      repeats: true
    ) { [weak self] _ in
      guard let self = self else { return }
      guard Defaults[.enableBrewAutoUpdate] else {
        Task { @MainActor in
          self.stopAllTimers()
        }
        return
      }

      print("自动检查Brew更新：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))")

      Task {
        await self.checkForUpdates(background: true)
      }
    }

    if let timer = autoCheckTimer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  private func startDailyTimer() {
    scheduleNextCheck(for: .daily)
  }

  private func startWeeklyTimer() {
    scheduleNextCheck(for: .weekly)
  }

  private func scheduleNextCheck(for frequency: BrewUpdateFrequency) {
    let nextCheckDate = calculateNextCheckDate(for: frequency)
    let timeInterval = nextCheckDate.timeIntervalSinceNow

    guard timeInterval > 0 else {
      // 如果计算出的时间已经过了，立即执行一次检查，然后重新计算下次时间
      Task {
        await checkForUpdates(background: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          self.scheduleNextCheck(for: frequency)
        }
      }
      return
    }

    scheduledCheckTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      guard Defaults[.enableBrewAutoUpdate] else {
        Task { @MainActor in
          self.stopAllTimers()
        }
        return
      }

      print("定时检查Brew更新：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))")

      Task {
        await self.checkForUpdates(background: true)
        // 检查完成后，安排下次检查
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          self.scheduleNextCheck(for: frequency)
        }
      }
    }

    if let timer = scheduledCheckTimer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  private func calculateNextCheckDate(for frequency: BrewUpdateFrequency) -> Date {
    let calendar = Calendar.current
    let now = Date()
    let scheduledTime = Defaults[.brewUpdateTime]

    // 获取设定的小时和分钟
    let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)

    switch frequency {
    case .hourly:
      // 小时频率不应该到这里，但为了安全起见
      return calendar.date(byAdding: .hour, value: 1, to: now) ?? now

    case .daily:
      // 计算今天的检查时间
      var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
      todayComponents.hour = timeComponents.hour
      todayComponents.minute = timeComponents.minute
      todayComponents.second = 0

      guard let todayCheckTime = calendar.date(from: todayComponents) else { return now }

      // 如果今天的检查时间还没到，就返回今天的时间；否则返回明天的时间
      if todayCheckTime > now {
        return todayCheckTime
      } else {
        return calendar.date(byAdding: .day, value: 1, to: todayCheckTime) ?? todayCheckTime
      }

    case .weekly:
      // 获取用户选择的星期几
      let selectedWeekday = Defaults[.brewUpdateWeekday]

      // 计算本周选择日期的检查时间
      var weekdayComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
      weekdayComponents.weekday = selectedWeekday.rawValue
      weekdayComponents.hour = timeComponents.hour
      weekdayComponents.minute = timeComponents.minute
      weekdayComponents.second = 0

      guard let thisWeekDate = calendar.date(from: weekdayComponents) else { return now }

      // 如果本周的检查时间还没到，就返回本周的时间；否则返回下周的时间
      if thisWeekDate > now {
        return thisWeekDate
      } else {
        return calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeekDate) ?? thisWeekDate
      }
    }
  }

  // 添加停止所有计时器的方法
  private func stopAllTimers() {
    autoCheckTimer?.invalidate()
    autoCheckTimer = nil
    scheduledCheckTimer?.invalidate()
    scheduledCheckTimer = nil
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
  @Default(.enableBrewAutoUpdate) private var isAutoUpdateEnabled
  @Default(.brewUpdateFrequency) private var updateFrequency
  @Default(.brewUpdateTime) private var updateTime
  @Default(.brewUpdateWeekday) private var updateWeekday

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      autoUpdateToggleView
      updateFrequencyPickerView
      updateScheduleSettingsView

      HStack {
        if observer.updateAppList.isEmpty {
          checkUpdateButton
          lastUpdatedView
        } else {
          updateInfoView
        }
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
        .frame(maxHeight: 800) // 限制高度, 防止内容过多导致布局问题
      }
    }
  }

  private var autoUpdateToggleView: some View {
    Toggle(isOn: $isAutoUpdateEnabled) {
      Text("Enable Auto Update", comment: "Toggle for enabling automatic brew updates")
    }
    .toggleStyle(SwitchToggleStyle())
    .onChange(of: isAutoUpdateEnabled) { _, newValue in
      observer.handleAutoUpdateSettingChange()
    }
  }

  private var updateFrequencyPickerView: some View {
    HStack {
      Text("Update Frequency", comment: "Label for update frequency selection")
      Spacer()
      Picker("Update Frequency", selection: $updateFrequency) {
        ForEach(BrewUpdateFrequency.allCases, id: \.self) { frequency in
          Text(frequency.localizedTitle).tag(frequency)
        }
      }
      .pickerStyle(MenuPickerStyle())
      .disabled(!isAutoUpdateEnabled)
      .onChange(of: updateFrequency) { _, newValue in
        observer.handleFrequencyChange()
      }
    }
  }

  @ViewBuilder
  private var updateScheduleSettingsView: some View {
    if updateFrequency == .daily {
      dailyUpdateSettingsView
    } else if updateFrequency == .weekly {
      weeklyUpdateSettingsView
    }
  }

  private var dailyUpdateSettingsView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Daily Update Settings", comment: "Header for daily update settings")
        .font(.headline)
        .foregroundColor(.primary)

      updateTimePickerView

      // 显示下次更新时间
      if isAutoUpdateEnabled {
        nextUpdateInfoView
      }
    }
    .padding(12)
    .background(.secondary.opacity(0.1))
    .cornerRadius(8)
  }

  private var weeklyUpdateSettingsView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Weekly Update Settings", comment: "Header for weekly update settings")
        .font(.headline)
        .foregroundColor(.primary)

      weekdayPickerView
      updateTimePickerView

      // 显示下次更新时间
      if isAutoUpdateEnabled {
        nextUpdateInfoView
      }
    }
    .padding(12)
    .background(.secondary.opacity(0.1))
    .cornerRadius(8)
  }

  private var weekdayPickerView: some View {
    HStack {
      Text("Update Day", comment: "Label for weekday selection")
      Spacer()
      Picker("Update Day", selection: $updateWeekday) {
        ForEach(BrewUpdateWeekday.allCases, id: \.self) { weekday in
          Text(weekday.localizedTitle).tag(weekday)
        }
      }
      .pickerStyle(MenuPickerStyle())
      .disabled(!isAutoUpdateEnabled)
      .onChange(of: updateWeekday) { _, newValue in
        observer.handleTimeChange()
      }
    }
  }

  private var updateTimePickerView: some View {
    HStack {
      Text("Update Time", comment: "Label for time selection")
      Spacer()

      // 使用更友好的时间选择器
      HStack(spacing: 4) {
        Text("at", comment: "Preposition before time")
          .foregroundColor(.secondary)

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
      }
    }
  }

  private var nextUpdateInfoView: some View {
    HStack {
      Image(systemName: "clock")
        .foregroundColor(.blue)
        .font(.caption)

      Text("Next update: \(nextUpdateTimeString)", comment: "Shows when the next update will occur")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }

  private var nextUpdateTimeString: String {
    let calendar = Calendar.current
    let now = Date()
    let scheduledTime = updateTime
    let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)

    switch updateFrequency {
    case .hourly:
      return NSLocalizedString("Every hour", comment: "Next update time for hourly frequency")

    case .daily:
      var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
      todayComponents.hour = timeComponents.hour
      todayComponents.minute = timeComponents.minute
      todayComponents.second = 0

      guard let todayCheckTime = calendar.date(from: todayComponents) else {
        return NSLocalizedString("Unknown", comment: "Unknown next update time")
      }

      let nextUpdate = todayCheckTime > now ? todayCheckTime : calendar.date(byAdding: .day, value: 1, to: todayCheckTime) ?? todayCheckTime

      let formatter = DateFormatter()
      if calendar.isDateInToday(nextUpdate) {
        formatter.dateFormat = "HH:mm"
        return String(format: NSLocalizedString("Today at %@", comment: "Next update today at specific time"), formatter.string(from: nextUpdate))
      } else if calendar.isDateInTomorrow(nextUpdate) {
        formatter.dateFormat = "HH:mm"
        return String(format: NSLocalizedString("Tomorrow at %@", comment: "Next update tomorrow at specific time"), formatter.string(from: nextUpdate))
      } else {
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: nextUpdate)
      }

    case .weekly:
      var weekdayComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
      weekdayComponents.weekday = updateWeekday.rawValue
      weekdayComponents.hour = timeComponents.hour
      weekdayComponents.minute = timeComponents.minute
      weekdayComponents.second = 0

      guard let thisWeekDate = calendar.date(from: weekdayComponents) else {
        return NSLocalizedString("Unknown", comment: "Unknown next update time")
      }

      let nextUpdate = thisWeekDate > now ? thisWeekDate : calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeekDate) ?? thisWeekDate

      let formatter = DateFormatter()
      formatter.dateFormat = "EEEE, MMM d, HH:mm"
      return formatter.string(from: nextUpdate)
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
