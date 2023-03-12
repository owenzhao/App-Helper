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
    
    @Default(.notifyUser) private var notifyUser
    
    private let notificatonErrorPublisher = NotificationCenter.default.publisher(for: .notificationError)
    private let notificationAuthorizeDeniedPublisher = NotificationCenter.default.publisher(for: .notificationAuthorizeDenied)
    
    @State private var error:MyError?
    @State private var showNotificationAuthorizeDeniedAlert = false
    
    var body: some View {
        WindowBinder(window: $window) {
            VStack(alignment: .leading) {
                Section {
                    Text("Rules")
                        .font(.title)
                    Toggle("Restart Monitor Control When System Preferences App Quits", isOn: $restartMonitorControl)
                    Toggle("Force Quitting SourceKitService When Xcode Quits", isOn: $forceQuitSourceKitService)
                    
                    Divider()
                }
                
                Section {
                    Text("Preferences")
                        .font(.title)
                    Toggle("Notify User when a rule is matched.", isOn: $notifyUser)
                    Divider()
                }
                
                Button("Run in Background") {
                    NotificationCenter.default.post(name: .simulatedWindowClose, object: self)
                }
            }
            .padding()
        }
        .onChange(of: window) { newValue in
            if let window = newValue {
                window.delegate = WindowDelegate.shared
                NotificationCenter.default.post(name: .updateWindow, object: nil, userInfo: ["window" : window])
            }
        }
        .onReceive(notificatonErrorPublisher) { notification in
            if let userInfo = notification.userInfo as? [String:Error], let error = userInfo["error"] {
                self.error = MyError(error)
            }
        }
        .onReceive(notificationAuthorizeDeniedPublisher, perform: { _ in
            showNotificationAuthorizeDeniedAlert = true
        })
        .alert(item: $error) { error in
            Alert(title: Text(error.error.localizedDescription), message: nil, dismissButton: Alert.Button.default(Text("OK")))
        }
        .alert(isPresented: $showNotificationAuthorizeDeniedAlert) {
            Alert(title: Text("Can't send notification!"),
                  message: Text("Notification is not allowed by user. Please check your system preferences."),
                  dismissButton: Alert.Button.default(Text("OK")))
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

struct MyError:Identifiable {
    let id = UUID()
    let error:Error
    
    init(_ error:Error) {
        self.error = error
    }
}
