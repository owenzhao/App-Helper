//
//  RulesView.swift
//  App Helper
//
//  Created by zhaoxin on 2023/3/11.
//

import AppleScriptObjC
import AppKit
import AVFoundation
import Darwin
import Defaults
import IOKit.pwr_mgt
import SwiftUI
import SwiftUIWindowBinder
import UniformTypeIdentifiers

struct RulesView: View {
  private let xcodeHighCPUThreshold = 1.0
  private let xcodeHighCPUSeconds = 30
  private let ruleCount = 6

  @State private var window: SwiftUIWindowBinder.Window?

  @Default(.restartMonitorControl) private var restartMonitorControl
  @Default(.monitorXcodeHighCPUUsage) private var monitorXcodeHighCPUUsage
  @Default(.forceQuitSourceKitService) private var forceQuitSourceKitService
  @Default(.forceQuitOpenAndSavePanelService) private var forceQuitOpenAndSavePanelService
  @Default(.cleanUpWebContentRemains) private var cleanUpWebContentRemains
  @Default(.cleanUpSafariRemainsAggressively) private var cleanUpSafariRemainsAggressively

  @Default(.notifyUser) private var notifyUser

  @Default(.autoStartApps) private var autoStartApps
  @Default(.startClashVerge) private var startClashVerge
  @Default(.startSwitchHosts) private var startSwitchHosts

  @Default(.enableSleepWatching) private var enableSleepWatching
  @Default(.sleepShortcut) private var sleepShortcut
  @State private var isRecordingShortcut = false

  @State private var preventScreensaver = false
  @State private var hideDesktop = false
  @State private var assertionID: IOPMAssertionID = 0
  @State private var sleepDisabled = false
  @State private var hdrStatus = NSLocalizedString("Checking...", comment: "Initial HDR status")
  @State private var currentHDRMode: Bool?

  private let notificatonErrorPublisher = NotificationCenter.default.publisher(for: .notificationError)
  private let notificationAuthorizeDeniedPublisher = NotificationCenter.default.publisher(for: .notificationAuthorizeDenied)
  private let screenParametersChangedPublisher = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
  private let hdrDisplayChangedPublisher = NotificationCenter.default.publisher(for: .ahHDRDisplayDidChange)

  @State private var error: MyError?
  @State private var showNotificationAuthorizeDeniedAlert = false
  @State private var pendingRemovalApp: AHApp?

  var body: some View {
    WindowBinder(window: $window) {
      Form {
        rulesSection
        preferencesSection
        commandsSection
        autoStartSection
        displaySection
        systemSleepSection
        footerSection
      }
      .formStyle(.grouped)
      .frame(minWidth: 560, minHeight: 520)
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
    .onAppear {
      HDRDisplayChangeNotifier.shared.start()
      migrateLegacyAutoStartAppsIfNeeded()
      refreshDesktopVisibility()
      refreshHDRStatus()
    }
    .onDisappear {
      HDRDisplayChangeNotifier.shared.stop()
    }
    .onReceive(screenParametersChangedPublisher) { _ in
      refreshHDRStatus()
    }
    .onReceive(hdrDisplayChangedPublisher) { _ in
      refreshHDRStatus()
    }
    .onReceive(notificationAuthorizeDeniedPublisher, perform: { _ in
      showNotificationAuthorizeDeniedAlert = true
    })
    .confirmationDialog(
      Text("Remove App", comment: "Remove app confirmation title"),
      isPresented: Binding(
        get: { pendingRemovalApp != nil },
        set: { isPresented in
          if isPresented == false {
            pendingRemovalApp = nil
          }
        }
      ),
      titleVisibility: .visible
    ) {
      Button("Remove", role: .destructive) {
        if let pendingRemovalApp {
          removeAutoStartApp(pendingRemovalApp)
          self.pendingRemovalApp = nil
        }
      }
      Button("Cancel", role: .cancel) {
        pendingRemovalApp = nil
      }
    } message: {
      if let pendingRemovalApp {
        Text(String.localizedStringWithFormat(
          NSLocalizedString("Are you sure you want to remove %@?", comment: "Remove app confirmation message"),
          pendingRemovalApp.name ?? pendingRemovalApp.url.deletingPathExtension().lastPathComponent
        ))
      }
    }
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

  func refreshDesktopVisibility() {
    let createDesktop = shell("defaults read com.apple.finder CreateDesktop")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    hideDesktop = createDesktop == "0" || createDesktop == "false"
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
      AHRuleToggle(
        title: NSLocalizedString("Restart Monitor Control When System Preferences App Quits", comment: "Rule: restart Monitor Control when a system settings app quits"),
        subtitle: NSLocalizedString("Restart Monitor Control after a system settings app quits.", comment: "Rule subtitle: restart Monitor Control"),
        systemImage: "arrow.triangle.2.circlepath",
        isOn: $restartMonitorControl
      )

      AHRuleToggle(
        title: xcodeHighCPUTitle,
        subtitle: NSLocalizedString("Watch Xcode's CPU usage and clean up when it stays above the threshold.", comment: "Rule subtitle: Xcode high CPU"),
        systemImage: "cpu",
        isOn: $monitorXcodeHighCPUUsage
      )

      AHRuleToggle(
        title: NSLocalizedString("Force Quitting SourceKitService When Xcode Quits", comment: "Rule: quit SourceKitService when Xcode quits"),
        subtitle: NSLocalizedString("Kill SourceKitService as soon as Xcode quits.", comment: "Rule subtitle: SourceKitService"),
        systemImage: "hammer",
        isOn: $forceQuitSourceKitService
      )

      AHRuleToggle(
        title: NSLocalizedString("Force Quitting Open and Save Panel Service When an App Quits", comment: "Rule: quit the Open and Save panel service"),
        subtitle: NSLocalizedString("Kill the Open and Save panel service when any app quits.", comment: "Rule subtitle: Open and Save panel service"),
        systemImage: "xmark.octagon",
        isOn: $forceQuitOpenAndSavePanelService
      )

      AHRuleToggle(
        title: NSLocalizedString("Clean Up Web Content Remains When an App Quits", comment: "Rule: clean up Web Content remains"),
        subtitle: NSLocalizedString("Remove leftover Web Content processes when an app quits.", comment: "Rule subtitle: Web Content remains"),
        systemImage: "trash",
        isOn: $cleanUpWebContentRemains
      )

      AHRuleToggle(
        title: NSLocalizedString("Clean Up Safari Remains Aggressively", comment: "Rule: clean up Safari remains aggressively"),
        subtitle: NSLocalizedString("Also clean up Safari-related leftovers more aggressively.", comment: "Rule subtitle: Safari remains"),
        systemImage: "safari",
        isOn: $cleanUpSafariRemainsAggressively
      )
    } header: {
      Text("Rules", comment: "Rules section title")
    } footer: {
      Text(rulesSummary)
    }
  }

  private var preferencesSection: some View {
    Section {
      AHRuleToggle(
        title: NSLocalizedString("Notify User when a rule is matched.", comment: "Preference: notify user when a rule is matched"),
        subtitle: NSLocalizedString("Send a system notification when a rule fires.", comment: "Preference subtitle: notification"),
        systemImage: "bell.badge",
        isOn: $notifyUser
      )
    } header: {
      Text("Preferences", comment: "Preferences section title")
    }
  }

  private var commandsSection: some View {
    Section {
      AHRuleToggle(
        title: NSLocalizedString("Prevent Screensaver.", comment: "Command: prevent the screensaver from starting"),
        subtitle: NSLocalizedString("Only applies until App Helper quits.", comment: "Command subtitle: session-only state"),
        systemImage: "eye",
        isOn: $preventScreensaver
      )
      .onChange(of: preventScreensaver) {
        if preventScreensaver {
          disableScreenSleep()
        } else {
          enableScreenSleep()
        }
      }

      AHRuleToggle(
        title: NSLocalizedString("Hide Desktop.", comment: "Command: hide the desktop icons"),
        subtitle: NSLocalizedString("Writes to Finder settings and persists.", comment: "Command subtitle: persisted state"),
        systemImage: "eye.slash",
        isOn: Binding(
          get: { hideDesktop },
          set: { hideDesktop in
            self.hideDesktop = hideDesktop
            showDesktop(!hideDesktop)
          }
        )
      )
    } header: {
      Text("Commands", comment: "Commands section title")
    }
  }

  private var autoStartSection: some View {
    Section {
      if autoStartApps.isEmpty {
        Text("No apps added.", comment: "Empty state for the auto start app list")
          .foregroundStyle(.secondary)
      } else {
        ForEach($autoStartApps) { $app in
          AHAppRow(app: $app) {
            pendingRemovalApp = app
          }
        }
      }
    } header: {
      HStack {
        Text("Start other apps after self starts", comment: "Auto start section title")
        Spacer()
        Button(action: chooseAutoStartApp) {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .help(NSLocalizedString("Add App", comment: "Auto start app picker confirm button"))
        .accessibilityLabel(Text("Add App", comment: "Auto start app picker confirm button"))
      }
    }
  }

  private var displaySection: some View {
    Section {
      Button {
        RulesView.toggleSystemAppearance()
      } label: {
        Label {
          Text("Toggle System Color Theme", comment: "Button to toggle system color theme")
        } icon: {
          Image(systemName: "circle.lefthalf.filled")
        }
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.tint)

      LabeledContent {
        HStack(spacing: 8) {
          AHStatusBadge(status: hdrStatus, mode: currentHDRMode)

          Button(action: refreshHDRStatus) {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(.borderless)
          .help(NSLocalizedString("Refresh HDR Status", comment: "Button to refresh HDR status"))
          .accessibilityLabel(Text("Refresh HDR Status", comment: "Button to refresh HDR status"))
        }
      } label: {
        Label {
          Text("HDR Status", comment: "HDR status row label")
        } icon: {
          Image(systemName: "display")
        }
      }
    } header: {
      Text("Display", comment: "Display section title")
    }
  }

  private var systemSleepSection: some View {
    Section {
      AHRuleToggle(
        title: NSLocalizedString("Monitor System Sleep", comment: "Toggle: monitor system sleep"),
        subtitle: NSLocalizedString("Run the shortcut below when the system is about to sleep.", comment: "System sleep toggle subtitle"),
        systemImage: "moon.zzz",
        isOn: $enableSleepWatching
      )

      LabeledContent {
        KeyboardShortcutView(
          shortcut: $sleepShortcut,
          isRecording: $isRecordingShortcut,
          specialKeysEnabled: true
        )
      } label: {
        Text("Sleep Shortcut", comment: "Sleep shortcut row label")
      }
      .disabled(!enableSleepWatching)
    } header: {
      Text("System Sleep", comment: "System sleep section title")
    }
  }

  private var footerSection: some View {
    Section {
      Button {
        NotificationCenter.default.post(name: .simulatedWindowClose, object: self)
      } label: {
        Label {
          Text("Run in Background", comment: "Button to hide the window and keep running in the background")
        } icon: {
          Image(systemName: "arrow.down.right.and.arrow.up.left")
        }
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.tint)
    }
  }
}

// MARK: - Row Components
private struct AHRuleToggle: View {
  let title: String
  let subtitle: String
  let systemImage: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: systemImage)
          .imageScale(.medium)
          .foregroundStyle(.secondary)
          .frame(width: 16, alignment: .center)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .fixedSize(horizontal: false, vertical: true)

          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .toggleStyle(.switch)
  }
}

private struct AHStatusBadge: View {
  let status: String
  let mode: Bool?

  private var tint: Color {
    switch mode {
    case .some(true):
      return .green
    case .some(false):
      return .secondary
    case .none:
      return .orange
    }
  }

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(tint)
        .frame(width: 7, height: 7)

      Text(status)
        .font(.callout.weight(.medium))
        .foregroundStyle(mode == nil ? Color.secondary : Color.primary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 2)
    .background(
      Capsule().fill(tint.opacity(0.15))
    )
    .accessibilityElement(children: .combine)
  }
}

private struct AHAppRow: View {
  @Binding var app: AHApp
  let onRemove: () -> Void

  @State private var isHovering = false

  private var displayName: String {
    app.name ?? app.url.deletingPathExtension().lastPathComponent
  }

  var body: some View {
    HStack(spacing: 6) {
      Toggle(isOn: $app.enabled) {
        HStack(spacing: 8) {
          Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
            .resizable()
            .frame(width: 16, height: 16)

          Text(displayName)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .toggleStyle(.switch)

      Button(role: .destructive, action: onRemove) {
        Image(systemName: "minus.circle.fill")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(isHovering ? Color.red : Color.secondary)
      .opacity(isHovering ? 1 : 0.35)
      .help(NSLocalizedString("Remove App", comment: "Remove app confirmation title"))
      .accessibilityLabel(Text("Remove App", comment: "Remove app confirmation title"))
    }
    .help(app.url.path)
    .onHover { isHovering = $0 }
  }
}

private extension RulesView {
  var rulesSummary: String {
    let enabled = [
      restartMonitorControl,
      monitorXcodeHighCPUUsage,
      forceQuitSourceKitService,
      forceQuitOpenAndSavePanelService,
      cleanUpWebContentRemains,
      cleanUpSafariRemainsAggressively,
    ].filter { $0 }.count

    return String.localizedStringWithFormat(
      NSLocalizedString("%lld of %lld rules enabled", comment: "Rules section footer summary"),
      Int64(enabled),
      Int64(ruleCount)
    )
  }

  var xcodeHighCPUTitle: String {
    let threshold = xcodeHighCPUThreshold.formatted(.percent.precision(.fractionLength(0)))
    let seconds = xcodeHighCPUSeconds.formatted()
    return String.localizedStringWithFormat(
      NSLocalizedString("Monitor Xcode High CPU Usage. (Over %@ and lasts %@ seconds.)", comment: "Rule title for Xcode high CPU monitoring"),
      threshold,
      seconds
    )
  }

  func chooseAutoStartApp() {
    let panel = NSOpenPanel()
    panel.title = NSLocalizedString("Choose App", comment: "Auto start app picker title")
    panel.message = NSLocalizedString("Choose an app to start automatically.", comment: "Auto start app picker message")
    panel.prompt = NSLocalizedString("Add App", comment: "Auto start app picker confirm button")
    panel.directoryURL = URL(filePath: "/Applications")
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.applicationBundle]

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }

    appendAutoStartApp(
      AHApp(
        name: url.deletingPathExtension().lastPathComponent,
        url: url,
        bundleID: Bundle(url: url)?.bundleIdentifier ?? "",
        enabled: true
      )
    )
  }

  func appendAutoStartApp(_ app: AHApp) {
    if let index = autoStartApps.firstIndex(where: { existing in
      if app.bundleID.isEmpty == false, existing.bundleID == app.bundleID {
        return true
      }

      return existing.url == app.url
    }) {
      autoStartApps[index] = app
    } else {
      autoStartApps.append(app)
    }
  }

  func removeAutoStartApp(_ app: AHApp) {
    autoStartApps.removeAll { existing in
      if app.bundleID.isEmpty == false, existing.bundleID == app.bundleID {
        return true
      }

      return existing.url == app.url
    }
  }

  func migrateLegacyAutoStartAppsIfNeeded() {
    if startClashVerge {
      appendAutoStartApp(
        AHApp(
          name: "Clash Verge",
          url: URL(filePath: "/Applications/Clash Verge.app/"),
          bundleID: Bundle(url: URL(filePath: "/Applications/Clash Verge.app/"))?.bundleIdentifier ?? "",
          enabled: true
        )
      )
      startClashVerge = false
    }

    if startSwitchHosts {
      appendAutoStartApp(
        AHApp(
          name: "SwitchHosts",
          url: URL(filePath: "/Applications/SwitchHosts.app/"),
          bundleID: Bundle(url: URL(filePath: "/Applications/SwitchHosts.app/"))?.bundleIdentifier ?? "",
          enabled: true
        )
      )
      startSwitchHosts = false
    }
  }

  typealias HDRBoolFunction = @convention(c) (CGDirectDisplayID) -> Bool

  enum HDRReader {
    private static let skyLightHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let slsSupportsHDRMode = loadFunction(named: "SLSDisplaySupportsHDRMode", in: skyLightHandle)
    private static let slsIsHDRModeEnabled = loadFunction(named: "SLSDisplayIsHDRModeEnabled", in: skyLightHandle)

    private static let coreGraphicsHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    private static let cgsIsHDRSupported = loadFunction(named: "CGSIsHDRSupported", in: coreGraphicsHandle)
    private static let cgsIsHDREnabled = loadFunction(named: "CGSIsHDREnabled", in: coreGraphicsHandle)

    private static func loadFunction(named symbol: String, in handle: UnsafeMutableRawPointer?) -> HDRBoolFunction? {
      guard let handle, let raw = dlsym(handle, symbol) else {
        return nil
      }

      return unsafeBitCast(raw, to: HDRBoolFunction.self)
    }

    static func hdrState(displayID: CGDirectDisplayID) -> (status: String, mode: Bool?) {
      if let slsSupportsHDRMode, let slsIsHDRModeEnabled {
        if slsSupportsHDRMode(displayID) == false {
          return (NSLocalizedString("Not Supported", comment: "Display does not support HDR"), nil)
        }

        return slsIsHDRModeEnabled(displayID)
          ? (NSLocalizedString("On", comment: "HDR mode enabled"), true)
          : (NSLocalizedString("Off", comment: "HDR mode disabled"), false)
      }

      guard let cgsIsHDRSupported, let cgsIsHDREnabled else {
        return (NSLocalizedString("Unavailable", comment: "Private HDR API unavailable"), nil)
      }

      if cgsIsHDRSupported(displayID) == false {
        return (NSLocalizedString("Not Supported", comment: "Display does not support HDR"), nil)
      }

      return cgsIsHDREnabled(displayID)
        ? (NSLocalizedString("On", comment: "HDR mode enabled"), true)
        : (NSLocalizedString("Off", comment: "HDR mode disabled"), false)
    }
  }

  func refreshHDRStatus() {
    guard let screen = NSScreen.main ?? NSScreen.screens.first,
          let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
      hdrStatus = NSLocalizedString("No Display", comment: "No display available for HDR check")
      currentHDRMode = nil
      return
    }

    let displayID = CGDirectDisplayID(screenNumber.uint32Value)
    let result = HDRReader.hdrState(displayID: displayID)
    hdrStatus = result.status
    currentHDRMode = result.mode
  }
}

struct RulesView_Previews: PreviewProvider {
  static var previews: some View {
    RulesView()
  }
}

struct AHApp: Codable, Defaults.Serializable, Identifiable, Equatable, Hashable {
  enum CodingKeys: String, CodingKey {
    case name
    case url
    case bundleID
    case enabled
  }

  var id: String { bundleID.isEmpty ? url.path : bundleID }
  let name: String?
  let url: URL
  let bundleID: String
  var enabled: Bool

  init(name: String?, url: URL, bundleID: String, enabled: Bool = true) {
    self.name = name
    self.url = url
    self.bundleID = bundleID
    self.enabled = enabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    url = try container.decode(URL.self, forKey: .url)
    bundleID = try container.decode(String.self, forKey: .bundleID)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
  }
}

struct MyError: Identifiable {
  let id = UUID()
  let error: Error

  init(_ error: Error) {
    self.error = error
  }
}

extension Notification.Name {
  static let ahHDRDisplayDidChange = Notification.Name("ahHDRDisplayDidChange")
}

private let hdrDisplayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, _, _ in
  DispatchQueue.main.async {
    NotificationCenter.default.post(name: .ahHDRDisplayDidChange, object: nil)
  }
}

private final class HDRDisplayChangeNotifier {
  static let shared = HDRDisplayChangeNotifier()
  private var isRegistered = false

  private init() {}

  func start() {
    guard isRegistered == false else {
      return
    }

    let result = CGDisplayRegisterReconfigurationCallback(hdrDisplayReconfigurationCallback, nil)
    isRegistered = result == .success
  }

  func stop() {
    guard isRegistered else {
      return
    }

    let result = CGDisplayRemoveReconfigurationCallback(hdrDisplayReconfigurationCallback, nil)
    if result == .success {
      isRegistered = false
    }
  }
}
