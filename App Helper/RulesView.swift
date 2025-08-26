//
//  RulesView.swift
//  App Helper
//
//  Created by zhaoxin on 2023/3/11.
//

import AppleScriptObjC
import AVFoundation
import Defaults
import IOKit.pwr_mgt
import SwiftUI
import SwiftUIWindowBinder

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

  @Default(.enableSleepWatching) private var enableSleepWatching
  @Default(.sleepShortcut) private var sleepShortcut
  @State private var isRecordingShortcut = false

  @State private var preventScreensaver = false
  @State private var hideDesktop = false
  @State private var assertionID: IOPMAssertionID = 0
  @State private var sleepDisabled = false

  private let notificatonErrorPublisher = NotificationCenter.default.publisher(for: .notificationError)
  private let notificationAuthorizeDeniedPublisher = NotificationCenter.default.publisher(for: .notificationAuthorizeDenied)

  @State private var error: MyError?
  @State private var showNotificationAuthorizeDeniedAlert = false

  var body: some View {
    WindowBinder(window: $window) {
      ScrollView {
        VStack(alignment: .leading) {
          rulesSection
          brewSection
          commandsSection
          autoStartSection
          displaySection
          systemSleepSection

          Button("Run in Background") {
            NotificationCenter.default.post(name: .simulatedWindowClose, object: self)
          }

          Spacer()
        }
      }
      .padding()
    }
    .onChange(of: window) { _, window in
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
      Alert(title: Text("Can't send notification!", comment: "Notification not allowed alert title"),
            message: Text("Notification is not allowed by user. Please check your system preferences.", comment: "Notification not allowed alert message"),
            dismissButton: Alert.Button.default(Text("OK", comment: "OK button")))
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

  static func toggleSystemAppearance() {
    let script = """
    tell application \"System Events\"
    set currentAppearance to (get appearance preferences)
    if (dark mode of currentAppearance is true) then
    set dark mode of currentAppearance to false
    else
    set dark mode of currentAppearance to true
    end if
    end tell
    """
    _ = runAppleScript(script)
  }
}

// MARK: - Section Views
extension RulesView {
  private var rulesSection: some View {
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

      preferencesSection
    }
  }

  private var preferencesSection: some View {
    Section {
      Text("Preferences")
        .font(.title2.bold())
      Toggle("Notify User when a rule is matched.", isOn: $notifyUser)
      Divider()
    }
  }

  private var commandsSection: some View {
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
  }

  private var autoStartSection: some View {
    Section {
      Text("Start other apps after self starts")
        .font(.title.bold())
      Toggle("Start SwitchHosts", isOn: $startSwitchHosts)
      Toggle("Start NightOwl", isOn: $startNightOwl)
      Divider()
    }
  }

  struct DisplaySectionView: View {
    var body: some View {
      Section {
        Text("Display", comment: "Display section title")
          .font(.title.bold())
        Button(action: RulesView.toggleSystemAppearance) {
          Text("Toggle System Color Theme", comment: "Button to toggle system color theme")
        }
        Divider()
      }
    }
  }

  private var displaySection: some View {
    DisplaySectionView()
  }

  private var brewSection: some View {
    Section {
      BrewView()
      Divider()
    }
  }

  private var systemSleepSection: some View {
    Section {
      Text("System Sleep")
        .font(.title.bold())

      HStack {
        Text("Sleep Shortcut:")
        KeyboardShortcutView(
          shortcut: $sleepShortcut,
          isRecording: $isRecordingShortcut,
          specialKeysEnabled: true
        )
      }
      .disabled(!enableSleepWatching)

      Toggle("Enable Sleep Watching", isOn: $enableSleepWatching)
        .toggleStyle(.switch)
    }
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
