//
//  Defaults.Keys.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import Defaults
import Foundation

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
}
