//
//  Defaults.Keys.Shared.swift
//  Stand Reminder
//
//  Created by zhaoxin on 2022/9/16.
//

import Defaults
import Foundation

let sharedDefaults = UserDefaults(suiteName: "96NM39SGJ5.com.parussoft.App-Helper.group")!

extension Defaults.Keys {
  public static let startFromLauncher = Key<Bool>("startFromLauncher", default: false, suite: sharedDefaults)
}
