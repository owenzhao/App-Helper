//
//  Defaults.Keys.Shared.swift
//  Stand Reminder
//
//  Created by zhaoxin on 2022/9/16.
//

import Foundation
import Defaults

let sharedDefaults = UserDefaults(suiteName: "96NM39SGJ5.com.parussoft.App-Helper-Launcher")!

extension Defaults.Keys {
    public static let startFromLauncher = Key<Bool>("startFromLauncher", default: false, suite: sharedDefaults)
}
