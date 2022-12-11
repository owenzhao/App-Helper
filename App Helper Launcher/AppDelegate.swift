//
//  AppDelegate.swift
//  App Helper Launcher
//
//  Created by zhaoxin on 2022/12/11.
//

import Cocoa
import Defaults

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        runInbackground()
        
        let pathComponents = Bundle.main.bundleURL.pathComponents
        let mainRange = 0..<(pathComponents.count - 4)
        let mainPath = pathComponents[mainRange].joined(separator: "/")
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: mainPath, isDirectory: false), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    private func runInbackground() {
        Defaults[.startFromLauncher] = true
    }
}

