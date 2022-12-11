//
//  WindowDelegate.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import Foundation
import AppKit

class WindowDelegate: NSObject, NSWindowDelegate {
    private override init() {
        super.init()
    }
    
    static let shared = WindowDelegate()
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NotificationCenter.default.post(name: .simulatedWindowClose, object: sender)
        return false
    }
}
