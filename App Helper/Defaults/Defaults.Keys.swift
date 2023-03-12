//
//  Defaults.Keys.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import Foundation
import Defaults

extension Defaults.Keys {
    static let autoLaunchWhenLogin = Key<Bool>("autoLaunchWhenLogin", default: true)
    
    static let restartMonitorControl = Defaults.Key<Bool>("Restart Monitor Control When System Preferences App Quits", default: false)
    static let forceQuitSourceKitService = Defaults.Key<Bool>("Force Quitting SourceKitService When Xcode Quits", default: false)
}
