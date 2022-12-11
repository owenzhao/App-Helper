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
    
    func startWatch() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemWillSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
    }
    
    func stopWatch() {
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self)
    }
    
    @objc private func systemWillSleep(_ noti:Notification) {
        let apps = Defaults[.apps]
        
        apps.forEach { app in
            if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first {
                runningApp.terminate()
            }
        }
    }
    
    @objc private func systemDidWake(_ noti:Notification) {
        let apps = Defaults[.apps]
        
        apps.forEach { app in
            if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first != nil {
                print("\(app.name ?? "The app") has already run.")
            } else {
                NSWorkspace.shared.open(app.url)
            }
        }
    }
}
