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
    static let apps = Defaults.Key<[AHApp]>("apps", default: [])
}
