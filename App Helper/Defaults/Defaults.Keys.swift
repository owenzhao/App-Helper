//
//  Defaults.Keys.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import Defaults
import Foundation

// Add enum for update frequencies
enum BrewUpdateFrequency: String, CaseIterable, Defaults.Serializable {
  case hourly = "hourly"
  case daily = "daily"
  case weekly = "weekly"

  var localizedTitle: String {
    switch self {
    case .hourly:
      return NSLocalizedString("Every Hour", comment: "Update frequency option for every hour")
    case .daily:
      return NSLocalizedString("Daily", comment: "Update frequency option for daily")
    case .weekly:
      return NSLocalizedString("Weekly", comment: "Update frequency option for weekly")
    }
  }
}

// Add enum for weekdays
enum BrewUpdateWeekday: Int, CaseIterable, Defaults.Serializable {
  case sunday = 1
  case monday = 2
  case tuesday = 3
  case wednesday = 4
  case thursday = 5
  case friday = 6
  case saturday = 7

  var localizedTitle: String {
    switch self {
    case .sunday:
      return NSLocalizedString("Sunday", comment: "Sunday weekday option")
    case .monday:
      return NSLocalizedString("Monday", comment: "Monday weekday option")
    case .tuesday:
      return NSLocalizedString("Tuesday", comment: "Tuesday weekday option")
    case .wednesday:
      return NSLocalizedString("Wednesday", comment: "Wednesday weekday option")
    case .thursday:
      return NSLocalizedString("Thursday", comment: "Thursday weekday option")
    case .friday:
      return NSLocalizedString("Friday", comment: "Friday weekday option")
    case .saturday:
      return NSLocalizedString("Saturday", comment: "Saturday weekday option")
    }
  }
}

extension Defaults.Keys {
  static let autoLaunchWhenLogin = Key<Bool>("autoLaunchWhenLogin", default: true)

  static let restartMonitorControl = Defaults.Key<Bool>("Restart Monitor Control When System Preferences App Quits", default: false)
  static let monitorXcodeHighCPUUsage = Defaults.Key<Bool>("Monitor Xcode High CPU Usage", default: false)
  static let forceQuitSourceKitService = Defaults.Key<Bool>("Force Quitting SourceKitService When Xcode Quits", default: false)
  static let forceQuitOpenAndSavePanelService = Defaults.Key<Bool>("forceQuitOpenAndSavePanelService", default: false)
  static let cleanUpWebContentRemains = Defaults.Key<Bool>("cleanUpWebContentRemains", default: false)
  static let cleanUpSafariRemainsAggressively = Defaults.Key<Bool>("cleanUpSafariRemainsAggressively", default: false)

  static let notifyUser = Defaults.Key<Bool>("Notify User when a rule is matched", default: true)

  static let startSwitchHosts = Defaults.Key<Bool>("startSwitchHosts", default: false)
  static let startNightOwl = Defaults.Key<Bool>("startNightOwl", default: false)

  static let lastBrewUpdateCheck = Defaults.Key<Date>("LastBrewUpdateCheck", default: Date.distantPast)
  static let enableBrewAutoUpdate = Defaults.Key<Bool>("EnableBrewAutoUpdate", default: true)
  static let brewUpdateFrequency = Defaults.Key<BrewUpdateFrequency>("BrewUpdateFrequency", default: .hourly)
  static let brewUpdateTime = Defaults.Key<Date>("BrewUpdateTime", default: {
    let calendar = Calendar.current
    let components = DateComponents(hour: 9, minute: 0) // Default to 9:00 AM
    return calendar.date(from: components) ?? Date()
  }())
  static let brewUpdateWeekday = Defaults.Key<BrewUpdateWeekday>("BrewUpdateWeekday", default: .monday)

  static let sleepShortcut = Key<String>("sleepShortcut", default: "Fn ⌃F12")
  static let enableSleepWatching = Key<Bool>("enableSleepWatching", default: true)
}
