//
//  SystemWatcher.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import Foundation
import AppKit
import Defaults
import UserNotifications
import CoreData

class SystemWatcher {
    private let moc: NSManagedObjectContext
    
    private init(moc:NSManagedObjectContext) {
        self.moc = moc
        startWatch()
    }
    static let shared = SystemWatcher(moc: LogProvider.shared.container.viewContext)
    
    lazy private var systemPreferences:AHApp = {
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = shell("mdls -name kMDItemCFBundleIdentifier -r '\(url.path)'")
        
        return AHApp(name: name, url: url, bundleID: bundleID)
    }()
    
    lazy private var appleIDSettings:AHApp = {
        let url = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/AppleIDSettings.appex")
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = shell("mdls -name kMDItemCFBundleIdentifier -r '\(url.path)'")
        
        return AHApp(name: name, url: url, bundleID: bundleID)
    }()
    
    lazy private var xcode:AHApp = {
        let url = URL(fileURLWithPath: "/Applications/Xcode.app")
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = shell("mdls -name kMDItemCFBundleIdentifier -r '\(url.path)'")
        
        return AHApp(name: name, url: url, bundleID: bundleID)
    }()
    
    lazy private var xcode_beta:AHApp = {
        let url = URL(fileURLWithPath: "/Applications/Xcode-beta.app")
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = shell("mdls -name kMDItemCFBundleIdentifier -r '\(url.path)'")
        
        return AHApp(name: name, url: url, bundleID: bundleID)
    }()
    
    lazy private var qqMusic:AHApp = {
        let url = URL(fileURLWithPath: "/Applications/QQMusic.app")
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = shell("mdls -name kMDItemCFBundleIdentifier -r '\(url.path)'")
        
        return AHApp(name: name, url: url, bundleID: bundleID)
    }()
    
    lazy private var safari:AHApp = {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = shell("mdls -name kMDItemCFBundleIdentifier -r '\(url.path)'")
        
        return AHApp(name: name, url: url, bundleID: bundleID)
    }()
    
    lazy private var mWebPro:AHApp = {
        let url = URL(fileURLWithPath: "/Applications/MWeb Pro.app")
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = shell("mdls -name kMDItemCFBundleIdentifier -r '\(url.path)'")
        
        return AHApp(name: name, url: url, bundleID: bundleID)
    }()
    
    func startWatch() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applyRules(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }
    
    func stopWatch() {
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self)
    }
    
    @objc private func applyRules(_ noti:Notification) {
        if Defaults[.restartMonitorControl] {
            if let userInfo = noti.userInfo,
               let terminatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               terminatedApp.bundleIdentifier == systemPreferences.bundleID {
                print("System Preferences App quits.")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                    let monitorControl:AHApp = {
                        let url = URL(fileURLWithPath: "/Applications/MonitorControl.app")
                        let name = url.deletingPathExtension().lastPathComponent
                        let bundleID = "me.guillaumeb.MonitorControl"
                        
                        return AHApp(name: name, url: url, bundleID: bundleID)
                    }()
                    
                    restartApp(check: appleIDSettings, restart: monitorControl)
                }
            }
        }
        
        if Defaults[.forceQuitSourceKitService] {
            if let userInfo = noti.userInfo,
               let terminatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               (terminatedApp.bundleIdentifier == xcode.bundleID || terminatedApp.bundleIdentifier == xcode_beta.bundleID) {
                print("Xcode or Xcode beta quits.")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                    quitService("SourceKitService", quitServiceName: "com.apple.dt.SKAgent")
                }
            }
        }
        
        if Defaults[.forceQuitOpenAndSavePanelService] {
            if let userInfo = noti.userInfo,
               let terminatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               let name = terminatedApp.localizedName {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                    quitOpenAndSavePanelService(with: name)
                }
            }
        }
        
        if Defaults[.cleanUpQQMusicRemains] {
            if let userInfo = noti.userInfo,
               let terminatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               terminatedApp.bundleIdentifier == qqMusic.bundleID {
                print("QQ Music quits.")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                    quitApps(with: "QQMusic网页内容")
                }
            }
        }
        
        if Defaults[.cleanUpSafariRemains] {
            if let userInfo = noti.userInfo,
               let terminatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               terminatedApp.bundleIdentifier == safari.bundleID {
                print("Safari quits.")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                    quitApps(with: "Safari网页内容")
                }
            }
        }
        
        if Defaults[.cleanUpMWebProRemains] {
            if let userInfo = noti.userInfo,
               let terminatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               terminatedApp.bundleIdentifier == mWebPro.bundleID {
                print("MWeb Pro quits.")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                    quitApps(with: "MWeb Pro网页内容")
                }
            }
        }
    }
    
    private func restartApp(check checkApp:AHApp, restart restartApp:AHApp) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: checkApp.bundleID).first != nil || true {
            if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: restartApp.bundleID).first {
                runningApp.terminate()
                run(restartApp)
            }
        }
    }
    
    private func quitService(_ checkServiceName:String, quitServiceName:String? = nil) {
        let pid = shell("pgrep \(checkServiceName)")
        
        guard pid.isEmpty == false else {
            return
        }
        
        let result = shell("pkill -9 \(quitServiceName ?? checkServiceName)")
        print("Killed \(result)")
        
        if Defaults[.notifyUser] {
            ruleApplied(name: checkServiceName, action: .quit)
        }
        
        addLog("\(checkServiceName) \(AHAction.quit.localizedString)")
    }
    
    private func quitApps(with name:String) {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.localizedName?.contains(name) == true }
        
        guard !apps.isEmpty else { return }
        
        var result = false
        
        apps.forEach {
            result = $0.terminate()
            
            if $0.isTerminated == false {
                result = $0.forceTerminate()
                
                if $0.isTerminated == false {
                    let r = shell("kill -9 \($0.processIdentifier)")
                    print("Killed \(r)")
                    
                    result = true // $0.isTerminated always returns false
                }
            }
        }
        
        if result {
            ruleApplied(name: name, action: .quit)
            addLog(String.localizedStringWithFormat(NSLocalizedString("Clean up %@ remains.", comment: ""), name))
        } else {
            addLog(String.localizedStringWithFormat(NSLocalizedString("Can not clean up %@.", comment: ""), name))
        }
    }
    
    private func quitOpenAndSavePanelService(with name:String) {
        let apps = NSWorkspace.shared.runningApplications
            .filter { ($0.localizedName?.hasPrefix("Open and Save Panel Service") == true
                       || $0.localizedName?.hasPrefix("QuickLookUIService") == true)
                && $0.localizedName?.contains(name) == true }
        
        guard !apps.isEmpty else { return }
        
        var result = false
        
        apps.forEach {
            result = $0.terminate()
            
            if $0.isTerminated == false {
                result = $0.forceTerminate()
                
                if $0.isTerminated == false {
                    let r = shell("kill -9 \($0.processIdentifier)")
                    print("Killed \(r)")
                    
                    result = true // $0.isTerminated always returns false
                }
            }
        }
        
        if result {
            ruleApplied(name: "Open and Save Panel Service \(name)", action: .quit)
            addLog(String.localizedStringWithFormat(NSLocalizedString("Quit %@", comment: ""), "Open and Save Panel Service \(name)"))
        } else {
            addLog(String.localizedStringWithFormat(NSLocalizedString("Can not quit %@.", comment: ""), "Open and Save Panel Service \(name)"))
        }
    }
    
    private func run(_ app:AHApp) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first == nil {
            NSWorkspace.shared.open(app.url)
            
            if Defaults[.notifyUser] {
                ruleApplied(name: app.name!, action: .restart)
            }
            
            addLog("\(app.name!) \(AHAction.restart.localizedString)")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                self.run(app)
            }
        }
    }
    
//    MARK: - Notification
    private func ruleApplied(name:String, action:AHAction) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization { granted, error in
                    if let error {
                        NotificationCenter.default.post(name: .notificationError, object: self, userInfo: ["error" : error])
                    }
                    
                    self.ruleApplied(name: name, action: action)
                }
            case .denied:
                NotificationCenter.default.post(name: .notificationAuthorizeDenied, object: self)
            case .authorized:
                fallthrough
            case .provisional:
                let content = UNMutableNotificationContent()
                content.title = NSLocalizedString("Rule Applied", comment: "")
                content.body = "\(name) \(action.localizedString)"
                
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(request)
            @unknown default:
                break
            }
        }
    }
    
//    MARK: - Logs
    private func addLog(_ text:String) {
        let log = AHLog(context: moc)
        log.createdDate = Date()
        log.text = text
        
        do {
            try moc.save()
        } catch {
            print(error)
        }
    }
}

enum AHAction:String {
    case restart
    case quit
    
    var localizedString:String {
        switch self {
        case .restart:
            return NSLocalizedString("restarted", comment: "")
        case .quit:
            return NSLocalizedString("quit", comment: "")
        }
    }
}
