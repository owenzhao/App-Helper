//
//  SystemWatcher.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import Foundation
import AppKit
import Defaults

class SystemWatcher {
    private init() {
        startWatch()
    }
    static let shared = SystemWatcher()
    
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
                        let url = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/AppleIDSettings.appex")
                        let name = url.deletingPathExtension().lastPathComponent
                        let bundleID = "me.guillaumeb.MonitorControl"
                        
                        return AHApp(name: name, url: url, bundleID: bundleID)
                    }()
                    
                    restartApp(appleIDSettings, restartApp: monitorControl)
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
    }
    
    private func restartApp(_ checkApp:AHApp, restartApp:AHApp) {
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
    }
    
    private func run(_ app:AHApp) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first == nil {
            NSWorkspace.shared.open(app.url)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                self.run(app)
            }
        }
    }
}
