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
import AppleScriptObjC

struct RulesView: View {
  @State private var window: SwiftUIWindowBinder.Window?

  @Default(.restartMonitorControl) private var restartMonitorControl
  @Default(.monitorXcodeHighCPUUsage) private var monitorXcodeHighCPUUsage
  @Default(.forceQuitSourceKitService) private var forceQuitSourceKitService
  @Default(.forceQuitOpenAndSavePanelService) private var forceQuitOpenAndSavePanelService
  @Default(.cleanUpWebContentRemains) private var cleanUpWebContentRemains
  @Default(.cleanUpSafariRemainsAggressively) private var cleanUpSafariRemainsAggressively

  @Default(.notifyUser) private var notifyUser

  @Default(.startSwitchHosts) private var startSwitchHosts
  @Default(.startNightOwl) private var startNightOwl

  @State private var preventScreensaver = false
  @State private var hideDesktop = false
  @State private var assertionID: IOPMAssertionID = 0
  @State private var sleepDisabled = false

  private let notificatonErrorPublisher = NotificationCenter.default.publisher(for: .notificationError)
  private let notificationAuthorizeDeniedPublisher = NotificationCenter.default.publisher(for: .notificationAuthorizeDenied)

  @State private var error: MyError?
  @State private var showNotificationAuthorizeDeniedAlert = false

  @State private var isHDROn: Bool = false

  var body: some View {
    WindowBinder(window: $window) {
      VStack(alignment: .leading) {
        Section {
          Text("Rules")
            .font(.title.bold())
          Toggle("Restart Monitor Control When System Preferences App Quits", isOn: $restartMonitorControl)
          Toggle("Monitor Xcode High CPU Usage. (Over 100% and lasts 30 seconds.)", isOn: $monitorXcodeHighCPUUsage)
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
          Toggle("Hide Desktop.", isOn: $hideDesktop)
            .onChange(of: hideDesktop) { _ in
              if hideDesktop {
                showDesktop(false)
              } else {
                showDesktop(true)
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

        Section {
          Text("Display")
            .font(.title.bold())
          Toggle("Enable HDR", isOn: $isHDROn)
            .onChange(of: isHDROn) { newValue in
              toggleHDR()
            }
            .toggleStyle(.switch)

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
      isHDROn = isHDREnabled()
    }
  }

  func disableScreenSleep(reason: String = "Disabling Screen Sleep") {
    if !sleepDisabled {
      sleepDisabled = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &assertionID) == kIOReturnSuccess
    }
  }

  func showDesktop(_ show: Bool) {
    if show {
      print(shell("defaults write com.apple.finder CreateDesktop true"))
    } else {
      print(shell("defaults write com.apple.finder CreateDesktop false"))
    }

    print(shell("killall Finder"))
  }

  func enableScreenSleep() {
    if sleepDisabled {
      IOPMAssertionRelease(assertionID)
      sleepDisabled = false
    }
  }

  func runAppleScript(_ script: String) -> (success: Bool, output: String?) {
    let trusted = AXIsProcessTrusted()
    if !trusted {
      let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
      AXIsProcessTrustedWithOptions(options)
      return (false, nil)
    }

    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", script]

    let pipe = Pipe()
    task.standardOutput = pipe

    do {
      try task.run()
      task.waitUntilExit()

      if task.terminationStatus == 0 {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (true, output)
      }
    } catch {
      print("运行AppleScript时出错：\(error)")
    }

    return (false, nil)
  }

  func toggleHDR() {
    let script = """
    tell application "System Settings"
    activate
    
    delay 1
    
    set the current pane to pane id "com.apple.Displays-Settings.extension"
    
    delay 1
    
    set isHDREnabled to true
    
    tell application "System Events" to tell application process "System Settings"
      tell group 3 of scroll area 2 of group 1 of group 2 of splitter group 1 of group 1 of window "显示器"
        try
          if (exists checkbox "高动态范围") then
            click checkbox "高动态范围"
          else
            set isHDREnabled to false
          end if
        end try
      end tell
      
      if (isHDREnabled is false) then
        tell group 4 of scroll area 2 of group 1 of group 2 of splitter group 1 of group 1 of window "显示器"
          click checkbox "高动态范围"
        end tell
      end if
    end tell
    
    tell application "System Settings" to quit
    end tell
    """

    let result = runAppleScript(script)
    if result.success {
      print("HDR状态已成功切换")
      isHDROn = isHDREnabled()
    } else {
      print("切换HDR状态失败")
    }
  }

  func isHDREnabled() -> Bool {
    let script = """
    tell application "System Settings"
    activate
    
    delay 1
    
    set the current pane to pane id "com.apple.Displays-Settings.extension"
    
    delay 1
    
    tell application "System Events" to tell application process "System Settings"
      tell group 3 of scroll area 2 of group 1 of group 2 of splitter group 1 of group 1 of window "显示器"
        if (exists checkbox "高动态范围") then
          return value of checkbox "高动态范围" as boolean
        end if
      end tell
      
      tell group 4 of scroll area 2 of group 1 of group 2 of splitter group 1 of group 1 of window "显示器"
        if (exists checkbox "高动态范围") then
          return value of checkbox "高动态范围" as boolean
        end if
      end tell
    end tell
    
    tell application "System Settings" to quit
    return false
    end tell
    """

    let result = runAppleScript(script)
    return result.success && result.output == "true"
  }
}

struct RulesView_Previews: PreviewProvider {
  static var previews: some View {
    RulesView()
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
