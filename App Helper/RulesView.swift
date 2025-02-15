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

  @State private var hdrEnabledAlert = false
  @State private var hdrDisabledAlert = false

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
            .onChange(of: preventScreensaver) {
              if preventScreensaver {
                disableScreenSleep()
              } else {
                enableScreenSleep()
              }
            }
          Toggle("Hide Desktop.", isOn: $hideDesktop)
            .onChange(of: hideDesktop) {
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

          Button("Switch HDR Status", action: RulesView.toggleHDR)
            .alert("HDR is enabled.", isPresented: $hdrEnabledAlert, actions: {})
            .alert("HDR is disabled", isPresented: $hdrDisabledAlert, actions: {})
            .onReceive(NotificationCenter.default.publisher(for: .hdrStatusChanged)) { notification in
              if let userInfo = notification.userInfo as? [String: String], let hdrStatus = userInfo["hdrStatus"] {
                if hdrStatus == "on" {
                  self.hdrEnabledAlert = true
                } else {
                  self.hdrDisabledAlert = true
                }
              }
            }

          Divider()
        }

        Section {
          Text("Brew")
            .font(.title.bold())

          BrewView()
          Divider()
        }

        Button("Run in Background") {
          NotificationCenter.default.post(name: .simulatedWindowClose, object: self)
        }

        Spacer()
      }
      .padding()
    }
    .onChange(of: window) {
      if let window {
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

  static func runAppleScript(_ script: String) -> (success: Bool, output: String?) {
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

  static func toggleHDR() {
    let script = """
    tell application "System Settings"
    activate
    
    -- 等待窗口出现。可根据电脑的性能进行调整。
    delay 0.5
    
    -- 显示所有子项
    -- return properties of every pane
    
    -- 打开显示器设置
    -- {class:pane, name:"显示器", id:"com.apple.Displays-Settings.extension"}
    set the current pane to pane id "com.apple.Displays-Settings.extension"
    
    delay 0.5
    
    -- 因为苹果脚本的特殊性，需要tell/ end tell等一一对应。所以，不能在第一段的try中的else中直接运行
    -- 具体的故障是，没有运行效果，checkbox不会被点击
    -- 因此，需要使用一个变量来进行转换。
    -- 先假设已经开启了HDR，如果不是，则设置为false，这样就可以运行第二段的if。
    set isHDREnabled to true
    set hdrStatus to "on"
    
    -- 使用系统事件
    tell application "System Events" to tell application process "System Settings"
    -- 这一步不是什么魔法，是一点儿一点儿试出来的。参考辅助代码
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
        set hdrStatus to "off"
      end tell
    end if
    end tell
    
    tell application "System Settings" to quit
    return hdrStatus
    end tell
    
    (* 辅助代码
    tell application "System Events" to tell application process "System Settings"
    tell group 4 of scroll area 2 of group 1 of group 2 of splitter group 1 of group 1 of window "显示器"
    return every UI element
    end tell
    end tell *)
    """

    let result = runAppleScript(script)
    if result.success {
      print("HDR状态已成功切换")
      NotificationCenter.default.post(name: .hdrStatusChanged, object: nil, userInfo: ["hdrStatus": result.output ?? "on"])
      NSSound.beep()
    } else {
      print("切换HDR状态失败")
    }
  }

  static func isHDREnabled() -> Bool {
    let script = """
    tell application "System Settings"
    activate
    
    -- 等待窗口出现。可根据电脑的性能进行调整。
    delay 0.5
    
    -- 显示所有子项
    -- return properties of every pane
    
    -- 打开显示器设置
    -- {class:pane, name:"显示器", id:"com.apple.Displays-Settings.extension"}
    set the current pane to pane id "com.apple.Displays-Settings.extension"
    
    delay 0.5
    
    -- 因为苹果脚本的特殊性，需要tell/ end tell等一一对应。所以，不能在第一段的try中的else中直接运行
    -- 具体的故障是，没有运行效果，checkbox不会被点击
    -- 因此，需要使用一个变量来进行转换。
    -- 先假设已经开启了HDR，如果不是，则设置为false，这样就可以运行第二段的if。
    set isHDREnabled to false
    
    -- 使用系统事件
    tell application "System Events" to tell application process "System Settings"
    -- 这一步不是什么魔法，是一点儿一点儿试出来的。参考辅助代码
    tell group 4 of scroll area 2 of group 1 of group 2 of splitter group 1 of group 1 of window "显示器"
      -- return exists checkbox "高动态范围"
      try
        if (exists checkbox "高动态范围") then
          set isHDREnabled to true
        end if
      end try
    end tell
    end tell
    
    tell application "System Settings" to quit
    
    return isHDREnabled
    end tell
    
    (* 辅助代码
    tell application "System Events" to tell application process "System Settings"
    tell group 4 of scroll area 2 of group 1 of group 2 of splitter group 1 of group 1 of window "显示器"
    return every UI element
    end tell
    end tell *)
    """

    let result = RulesView.runAppleScript(script)
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
