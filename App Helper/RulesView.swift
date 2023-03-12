//
//  RulesView.swift
//  App Helper
//
//  Created by zhaoxin on 2023/3/11.
//

import SwiftUI
import Defaults
import SwiftUIWindowBinder

struct RulesView: View {
    @State private var window: SwiftUIWindowBinder.Window?
    
    @Default(.restartMonitorControl) private var restartMonitorControl
    @Default(.forceQuitSourceKitService) private var forceQuitSourceKitService
    
    var body: some View {
        WindowBinder(window: $window) {
            VStack(alignment: .leading) {
                Toggle("Restart Monitor Control When System Preferences App Quits", isOn: $restartMonitorControl)
                Toggle("Force Quitting SourceKitService When Xcode Quits", isOn: $forceQuitSourceKitService)

                Button("Run in Background") {
                    NotificationCenter.default.post(name: .simulatedWindowClose, object: self)
                }
            }
            .toggleStyle(.switch)
        }
        .onChange(of: window) { newValue in
            if let window = newValue {
                window.delegate = WindowDelegate.shared
                NotificationCenter.default.post(name: .updateWindow, object: nil, userInfo: ["window" : window])
            }
        }
    }
}

struct RulesView_Previews: PreviewProvider {
    static var previews: some View {
        RulesView()
    }
}

struct AHApp:Codable, Defaults.Serializable, Identifiable, Equatable, Hashable {
    var id:String  { return bundleID }
    let name:String?
    let url:URL
    let bundleID:String
}
