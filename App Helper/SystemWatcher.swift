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
    
    func startWatch() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemPreferencesDidTerminate(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }
    
    func stopWatch() {
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self)
    }
    
    @objc private func systemPreferencesDidTerminate(_ noti:Notification) {
        if let userInfo = noti.userInfo,
           let runningApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           runningApp.bundleIdentifier == systemPreferences.bundleID {
            print("System Preferences App quits.")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                if NSRunningApplication.runningApplications(withBundleIdentifier: appleIDSettings.bundleID).first != nil {
                    let apps = Defaults[.apps]
                    
                    apps.forEach { app in
                        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first {
                            runningApp.terminate()
                            run(app)
                        }
                    }
                }
            }
        }
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
