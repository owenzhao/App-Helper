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
    
    lazy private var safari:AHApp = {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let name = url.deletingPathExtension().lastPathComponent
        let bundleID = shell("mdls -name kMDItemCFBundleIdentifier -r '\(url.path)'")
        
        return AHApp(name: name, url: url, bundleID: bundleID)
    }()
    
    private var timer:Timer?
    
    func startWatch() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applyRules(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { _ in
            self.timerRules()
        })
    }
    
    func stopWatch() {
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self)
        timer?.invalidate()
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
                    if NSWorkspace.shared.runningApplications
                        .filter({ $0.localizedName == terminatedApp.localizedName })
                        .isEmpty == true {
                        quitOpenAndSavePanelService(with: name)
                    }
                }
            }
        }
        
        if Defaults[.cleanUpWebContentRemains] {
            if let userInfo = noti.userInfo,
               let terminatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               var name = terminatedApp.localizedName {
                if name == "QQ音乐" {
                    name = "QQMusic"
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                    if NSWorkspace.shared.runningApplications
                        .filter({ $0.localizedName == terminatedApp.localizedName })
                        .isEmpty == true {
                        quitWebContent(with: name)
                    }
                }
            }
        }
        
        if Defaults[.cleanUpSafariRemainsAggressively] {
            if let userInfo = noti.userInfo,
               let terminatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               terminatedApp.bundleIdentifier == safari.bundleID {
                print("Safari quits.")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                    let excludingApps = [
                        "com.apple.Safari.History",
                        "SafariBookmarksSyncAgent",
                        "SafariLaunchAgent",
                        "SafariNotificationAgent",
                        "com.apple.Safari.SafeBrowsing.Service"
                    ]
                    quitSerice(with: "Safari", exclude: excludingApps)
                }
            }
        }
    }
    
    private func timerRules() {
        if Defaults[.startSwitchHosts] {
            let appURL = URL(filePath: "/Applications/SwitchHosts.app/")
            let ws = NSWorkspace.shared
            
            if ws.runningApplications.filter({ $0.bundleURL == appURL }).isEmpty {
                let result = ws.open(appURL)
                
                if Defaults[.notifyUser] {
                    ruleApplied(name: "SwitchHosts", action: result ? .restart : .failed)
                }
                
                if result {
                    addLog("SwitchHosts \(AHAction.start.localizedString)")
                } else {
                    addLog("SwitchHosts \(AHAction.start.localizedString) \(AHAction.failed.localizedString)")
                }
            }
        }
        
        if Defaults[.startNightOwl] {
            let appURL = URL(filePath: "/Applications/NightOwl.app/")
            let ws = NSWorkspace.shared
            
            if ws.runningApplications.filter({ $0.bundleURL == appURL }).isEmpty {
                let result = ws.open(appURL)
                
                if Defaults[.notifyUser] {
                    ruleApplied(name: "NightOwl", action: result ? .restart : .failed)
                }
                
                if result {
                    addLog("NightOwl \(AHAction.start.localizedString)")
                } else {
                    addLog("NightOwl \(AHAction.start.localizedString) \(AHAction.failed.localizedString)")
                }
            }
        }
    }
    
    private func restartApp(check checkApp:AHApp, restart restartApp:AHApp) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: checkApp.bundleID).first != nil {
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
    
    private func quitWebContent(with name:String) {
        quitSerice(with: name, services: ["网页内容", "Web Content"])
    }
    
    private func quitOpenAndSavePanelService(with name:String) {
        let services = [
            "Open and Save Panel Service",
            "QuickLookUIService"
        ]
        quitSerice(with: name, services: services)
    }
    
    private func quitSerice(with name:String, services:[String]) {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.contains(in: services) && $0.localizedName?.contains(name) == true }
        
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
            ruleApplied(name: apps.first!.localizedName!, action: .quit)
            addLog(String.localizedStringWithFormat(NSLocalizedString("Quit %@", comment: ""), apps.first!.localizedName!))
        } else {
            addLog(String.localizedStringWithFormat(NSLocalizedString("Can not quit %@.", comment: ""), apps.first!.localizedName!))
        }
    }
    
    private func quitSerice(with name:String, exclude excludingApps:[String]) {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.localizedName?.contains(name) == true }
            .filter { $0.contains(in: excludingApps) == false }
        
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
            ruleApplied(name: apps.first!.localizedName!, action: .quit)
            addLog(String.localizedStringWithFormat(NSLocalizedString("Quit %@", comment: ""), apps.first!.localizedName!))
        } else {
            addLog(String.localizedStringWithFormat(NSLocalizedString("Can not quit %@.", comment: ""), apps.first!.localizedName!))
        }
    }
    
    private func run(_ app:AHApp) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first == nil {
            let result = NSWorkspace.shared.open(app.url)
            
            if Defaults[.notifyUser] {
                ruleApplied(name: app.name!, action: result ? .restart : .failed)
            }
            
            if result {
                addLog("\(app.name!) \(AHAction.restart.localizedString)")
            } else {
                addLog("\(app.name!) \(AHAction.restart.localizedString) \(AHAction.failed.localizedString)")
            }
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
    case start
    case restart
    case quit
    case failed
    
    var localizedString:String {
        switch self {
        case .start:
            return NSLocalizedString("started", comment: "")
        case .restart:
            return NSLocalizedString("restarted", comment: "")
        case .quit:
            return NSLocalizedString("quit", comment: "")
        case .failed:
            return NSLocalizedString("failed", comment: "")
        }
    }
}

extension NSRunningApplication {
    func contains(in service:[String]) -> Bool {
        for service in service {
            if self.localizedName?.contains(service) == true {
                return true
            }
        }
        
        return false
    }
}
