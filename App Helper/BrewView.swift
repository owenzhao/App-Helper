//
//  BrewView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/2/8.
//

import Defaults
import SwiftUI
import UserNotifications

// Create an ObservableObject to handle system notifications
@MainActor
class BrewUpdateObserver: ObservableObject {
  static let shared = BrewUpdateObserver() // Convert to singleton
  private var notificationCenter: NotificationCenter
  @Published var updateAppList: [String] = [] // Add this property
  @Published var isLoading: Bool = false // Add loading state
  @Published var showBrewHasNoUpdate: Bool = false // Add no update prompt state
  @Published var showBrewUpgradeAlert: Bool = false // Add upgrade prompt state
  @Published var brewUpgradeResult: String? = nil // Add upgrade result

  // Modify timer related properties - simplify to single timer
  private var minuteTimer: Timer?
  // Add current task cancellation token
  private var currentCheckTask: Task<Void, Never>?

  private init() {
    notificationCenter = NSWorkspace.shared.notificationCenter
    setupObservers()

    // Start auto check on initialization
    startAutoCheckIfEnabled()
  }

  private func setupObservers() {
    // Listen for system wake
    notificationCenter.addObserver(
      self,
      selector: #selector(handleSystemWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
  }

  @objc private func handleSystemWake() {
    print("Awake at: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))")

    // Restart auto check to ensure normal operation after system sleep
    startAutoCheckIfEnabled()
  }

  // Add update check method
  // First, create a custom global actor for background operations
  @globalActor actor BrewBackgroundActor {
    static let shared = BrewBackgroundActor()
    private init() {}
  }

  // Modified checkForUpdates function
  func checkForUpdates(background: Bool = false) async {
    // If it's a background check and auto update is disabled, return directly
    if background && !Defaults[.enableBrewAutoUpdate] {
      return
    }

    // Cancel previous task
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

        // Check if task is cancelled
        if Task.isCancelled {
          return
        }

        // Execute brew operations in background thread
        let updates = await Task.detached {
          BrewService.shared.checkBrewUpdate()
        }.value

        // Check again if task is cancelled
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
          print("Error checking for updates: \(error)")
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

  // Add upgrade method
  func performUpgrade() async {
    await MainActor.run { isLoading = true }

    defer {
      Task { @MainActor in
        isLoading = false
      }
    }

    do {
      try await Task.sleep(nanoseconds: 1000)

      // Execute brew upgrade operation in background thread
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
      print("Error during upgrade: \(error)")

      await MainActor.run {
        brewUpgradeResult = error.localizedDescription
        showBrewUpgradeAlert = true
      }
    }
  }

  private func sendUpdateNotification(packages: [String]) {
    let content = UNMutableNotificationContent()
    content.title = NSLocalizedString("Homebrew Update Available", comment: "Notification title for Homebrew updates")
    content.body = String(format: NSLocalizedString("Found %d packages to update: %@", comment: "Notification body for Homebrew updates"), packages.count, packages.joined(separator: ", "))
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("Failed to send notification: \(error.localizedDescription)")
      }
    }
  }

  // Rewrite auto check startup method - unified use of minute-level detection
  private func startAutoCheckIfEnabled() {
    // Stop existing timers first
    stopAllTimers()

    // Only create timer when auto update is enabled
    guard Defaults[.enableBrewAutoUpdate] else { return }

    // Start minute-level detection timer
    startMinuteTimer()
  }

  private func startMinuteTimer() {
    minuteTimer = Timer.scheduledTimer(
      withTimeInterval: 60, // Check every minute
      repeats: true
    ) { [weak self] _ in
      guard let self = self else { return }
      guard Defaults[.enableBrewAutoUpdate] else {
        Task { @MainActor in
          self.stopAllTimers()
        }
        return
      }

      // Check if update is needed - execute on main thread
      Task { @MainActor in
        self.checkAndPerformUpdateIfNeeded()
      }
    }

    if let timer = minuteTimer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  // New core detection method
  private func checkAndPerformUpdateIfNeeded() {
    let frequency = Defaults[.brewUpdateFrequency]
    let lastUpdateDate = Defaults[.lastBrewUpdateCheck]

    if shouldPerformUpdateNow(lastUpdate: lastUpdateDate, frequency: frequency) {
      print("Scheduled check detected update needed: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))")

      Task {
        await checkForUpdates(background: true)
      }
    }
  }

  // Refactor judgment logic - determine whether to execute update immediately based on current time point
  private func shouldPerformUpdateNow(lastUpdate: Date, frequency: BrewUpdateFrequency) -> Bool {
    let calendar = Calendar.current
    let now = Date()
    let scheduledTime = Defaults[.brewUpdateTime]
    let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)

    // If never updated before, need to update
    if lastUpdate == Date.distantPast {
      return true
    }

    switch frequency {
    case .hourly:
      // Hourly frequency: if more than 1 hour since last update, need to update
      return now.timeIntervalSince(lastUpdate) >= 60 * 60

    case .daily:
      // Daily frequency: check if should update today and haven't updated yet
      let today = calendar.startOfDay(for: now)

      // If already updated today, no need to update again
      if calendar.isDate(lastUpdate, inSameDayAs: now) {
        return false
      }

      // Build today's update time point
      var todayUpdateComponents = calendar.dateComponents([.year, .month, .day], from: today)
      todayUpdateComponents.hour = timeComponents.hour
      todayUpdateComponents.minute = timeComponents.minute
      todayUpdateComponents.second = 0

      guard let todayUpdateTime = calendar.date(from: todayUpdateComponents) else { return false }

      // If today's update time has passed and haven't updated today, need to update
      return now >= todayUpdateTime

    case .weekly:
      let selectedWeekday = Defaults[.brewUpdateWeekday]

      // Check if should update this week and haven't updated yet
      let thisWeekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
      let lastUpdateWeekInterval = calendar.dateInterval(of: .weekOfYear, for: lastUpdate)

      // If already updated this week, no need to update again
      if let thisWeek = thisWeekInterval, let lastWeek = lastUpdateWeekInterval,
         thisWeek.start == lastWeek.start {
        return false
      }

      // Build this week's update time point
      var thisWeekUpdateComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
      thisWeekUpdateComponents.weekday = selectedWeekday.rawValue
      thisWeekUpdateComponents.hour = timeComponents.hour
      thisWeekUpdateComponents.minute = timeComponents.minute
      thisWeekUpdateComponents.second = 0

      guard let thisWeekUpdateTime = calendar.date(from: thisWeekUpdateComponents) else { return false }

      // If this week's update time has passed and haven't updated this week, need to update
      return now >= thisWeekUpdateTime
    }
  }

  // Add stop all timers method
  private func stopAllTimers() {
    minuteTimer?.invalidate()
    minuteTimer = nil
  }

  // Add public methods to handle setting changes
  func handleAutoUpdateSettingChange() {
    if Defaults[.enableBrewAutoUpdate] {
      startAutoCheckIfEnabled()
    } else {
      stopAllTimers()
      // Cancel current check task
      currentCheckTask?.cancel()
      currentCheckTask = nil

      // Stop loading state if currently loading
      Task { @MainActor in
        if isLoading {
          isLoading = false
        }
      }
    }
  }

  // Add method to handle frequency changes
  func handleFrequencyChange() {
    // Restart check if auto update is enabled
    if Defaults[.enableBrewAutoUpdate] {
      startAutoCheckIfEnabled()
    }
  }

  // Add method to handle time changes
  func handleTimeChange() {
    // Restart check if auto update is enabled and not hourly frequency
    if Defaults[.enableBrewAutoUpdate] && Defaults[.brewUpdateFrequency] != .hourly {
      startAutoCheckIfEnabled()
    }
  }

  deinit {
    notificationCenter.removeObserver(self)
    // When object is released, Timer callback will safely return early due to [weak self]
    // All Timers are automatically cleaned up by system when app exits
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
        // Remove forced detection, let timer automatically judge based on time rules
      }
  }

  private func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
      if granted {
        print("Notification permission granted")
      } else if let error = error {
        print("Failed to request notification permission: \(error.localizedDescription)")
      }
    }
  }
}

// Separate view logic into subview
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
        // Combined left content area
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
        Text("Update Brew", comment: "Toggle for enabling automatic brew updates")
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
      // Check update button
      checkUpdateButton

      // Last update time
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

      // Simple update setting information
      if isAutoUpdateEnabled {
        VStack(alignment: .trailing, spacing: 2) {
          Text("Update Frequency: \(updateFrequency.localizedTitle)", comment: "Update frequency display")
            .font(.subheadline)
            .foregroundColor(.primary)

          Text("Next Update: \(nextUpdateTimeString)", comment: "Next update time display")
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
        return String(format: NSLocalizedString("Today %@", comment: "Next update today at specific time"), formatter.string(from: nextUpdate))
      } else if calendar.isDateInTomorrow(nextUpdate) {
        formatter.dateFormat = "HH:mm"
        return String(format: NSLocalizedString("Tomorrow %@", comment: "Next update tomorrow at specific time"), formatter.string(from: nextUpdate))
      } else {
        formatter.dateFormat = "MMM dd HH:mm"
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
      formatter.dateFormat = "EEEE MMM dd HH:mm"
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
        // Main settings content area
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

        // Bottom fixed button
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
        return String(format: NSLocalizedString("Today %@", comment: "Next update today at specific time"), formatter.string(from: nextUpdate))
      } else if calendar.isDateInTomorrow(nextUpdate) {
        formatter.dateFormat = "HH:mm"
        return String(format: NSLocalizedString("Tomorrow %@", comment: "Next update tomorrow at specific time"), formatter.string(from: nextUpdate))
      } else {
        formatter.dateFormat = "MMM dd HH:mm"
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
      formatter.dateFormat = "EEEE MMM dd HH:mm"
      return formatter.string(from: nextUpdate)
    }
  }
}
