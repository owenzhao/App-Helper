//
//  RulesView.swift
//  App Helper
//
//  Created by zhaoxin on 2023/3/11.
//

import Defaults
import IOKit.pwr_mgt
import SwiftUI
import SwiftUIWindowBinder

struct RulesView: View {
  @State private var window: SwiftUIWindowBinder.Window?

  @Default(.restartMonitorControl) private var restartMonitorControl
  @Default(.forceQuitSourceKitService) private var forceQuitSourceKitService
  @Default(.forceQuitOpenAndSavePanelService) private var forceQuitOpenAndSavePanelService
  @Default(.cleanUpWebContentRemains) private var cleanUpWebContentRemains
  @Default(.cleanUpSafariRemainsAggressively) private var cleanUpSafariRemainsAggressively

  @Default(.notifyUser) private var notifyUser

  @Default(.startSwitchHosts) private var startSwitchHosts
  @Default(.startNightOwl) private var startNightOwl

  @Binding var preventScreensaver: Bool
  @Binding var assertionID: IOPMAssertionID
  @Binding var sleepDisabled: Bool

  private let notificatonErrorPublisher = NotificationCenter.default.publisher(for: .notificationError)
  private let notificationAuthorizeDeniedPublisher = NotificationCenter.default.publisher(for: .notificationAuthorizeDenied)

  @State private var error: MyError?
  @State private var showNotificationAuthorizeDeniedAlert = false

  var body: some View {
    WindowBinder(window: $window) {
      VStack(alignment: .leading) {
        Section {
          Text("Rules")
            .font(.title.bold())
          Toggle("Restart Monitor Control When System Preferences App Quits", isOn: $restartMonitorControl)
          Toggle("Force Quitting SourceKitService When Xcode Quits", isOn: $forceQuitSourceKitService)
          Toggle("Force Quitting Open and Save Panel Service When an App Quits", isOn: $forceQuitOpenAndSavePanelService)
          Toggle("Clean Up Web Content Remains When an App Quits", isOn: $cleanUpWebContentRemains)
          Toggle("Clean Up Safari Remains Aggressively", isOn: $cleanUpSafariRemainsAggressively)

          Divider()

          Section {
            Text("Preferences")
              .font(.title2.bold())
            Toggle("Notify User when a rule is matched.", isOn: $notifyUser)
          }

          Divider()
        }

        Section {
          Text("Commands")
            .font(.title.bold())
          Toggle("Prevent Screensaver.", isOn: $preventScreensaver)
            .onChange(of: preventScreensaver) { _ in
              if preventScreensaver {
                disableScreenSleep()
              } else {
                enableScreenSleep()
              }
            }
          Divider()
        }

        Section {
          Text("Start other apps after self starts")
            .font(.title.bold())

          Toggle("Start SwitchHosts", isOn: $startSwitchHosts)
          Toggle("Start NightOwl", isOn: $startNightOwl)

          Divider()
        }

        Button("Run in Background") {
          NotificationCenter.default.post(name: .simulatedWindowClose, object: self)
        }

        Spacer()
      }
      .padding()
    }
    .onChange(of: window) { newValue in
      if let window = newValue {
        window.delegate = WindowDelegate.shared
        NotificationCenter.default.post(name: .updateWindow, object: nil, userInfo: ["window": window])
      }
    }
    .onReceive(notificatonErrorPublisher) { notification in
      if let userInfo = notification.userInfo as? [String: Error], let error = userInfo["error"] {
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
    .onAppear {
      print(preventScreensaver)
    }
  }

  func disableScreenSleep(reason: String = "Disabling Screen Sleep") {
    if !sleepDisabled {
      sleepDisabled = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &assertionID) == kIOReturnSuccess
    }
  }

  func enableScreenSleep() {
    if sleepDisabled {
      IOPMAssertionRelease(assertionID)
      sleepDisabled = false
    }
  }
}

struct RulesView_Previews: PreviewProvider {
  static var previews: some View {
    RulesView(preventScreensaver: .constant(false),
              assertionID: .constant(0),
              sleepDisabled: .constant(false))
  }
}

struct AHApp: Codable, Defaults.Serializable, Identifiable, Equatable, Hashable {
  var id: String { return bundleID }
  let name: String?
  let url: URL
  let bundleID: String
}

struct MyError: Identifiable {
  let id = UUID()
  let error: Error

  init(_ error: Error) {
    self.error = error
  }
}
