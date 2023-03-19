//
//  LogProvider.swift
//  App Helper
//
//  Created by zhaoxin on 2023/3/19.
//

import Foundation
import CoreData
import AppKit

class LogProvider:ObservableObject {
    let container = NSPersistentContainer(name: "Model")
    
    private init() {
        container.loadPersistentStores { description, error in
            if let error = error {
                let alert = NSAlert(error: error)
                NSSound.beep()
                alert.runModal()
            }
        }
    }
    
    static let shared = LogProvider()
}
